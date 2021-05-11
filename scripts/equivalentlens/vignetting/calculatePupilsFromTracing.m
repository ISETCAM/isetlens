%% Calculate pupil from ray tracing
%
% The lens is samples for multiple off-axis positions. At each off
% axis-position the domain of rays that pass (entrance pupil) will vary and
% be described by the intersection of 3 circles. This script aims to
% automatically estimate the 3 circles.


% Thomas Goossens

%% Load lens file
clear;close all;

lensFileName = fullfile('dgauss.22deg.3.0mm.json');
%lensFileName = fullfile('tessar.22deg.3.0mm.json');
exist(lensFileName,'file');


lens = lensC('fileName', lensFileName)
lens=lensReverse(lensFileName);


%% Modifcation of lens parameters if desired
diaphragm_diameter=0.6;
lens.surfaceArray(6).apertureD=diaphragm_diameter
lens.apertureMiddleD=diaphragm_diameter

% Note there seems to be a redundancy in the lens which can get out of
% sync: lens.apertureMiddleD en lens.surfaceArray{i}.apertureD (i= index of
% middle aperture)
% lens.surfaceArray(6).apertureD=0.4 seems to be only used for drawing
%   lens.apertureMiddleD seems to be used for actual calculations in
%   determining the exit and entrance pupil


%% Choose entrance pupil position w.r.t. input plane
% Ideally this distance is chosen in the plane in which the entrance pupil
% doesn't shift.  

entrancepupil_distance =  1.1439;

%% Run ray trace, and log which rays can pass
clear p;

flag_runraytrace=false;

if(not(flag_runraytrace))
    % IF we don't want to redo all the ray trace, load a cached ray trace
    % file.
    load cache/dgauss-aperture0.6-sample250.mat;
else
    
    thetas = linspace(-40,40,250);
    phis = linspace(0,359,250);
    
    
    positions=[0 0.2 0.5 0.55 0.63 0.65 0.66 0.67]
    
    
    % Initiate the arrays as NaNs, else the zeros will be interpreted at a
    % position for which a ray passed
    pupilshape_trace = nan(3,numel(positions),numel(thetas),numel(phis));
    
    for p=1:numel(positions)
        p
        for ph=1:numel(phis)
            for t=1:numel(thetas)
                
                % Origin of ray
                origin = [0;positions(p);-2];
                
                
                % Direction vector of ray
                phi=phis(ph);
                theta=thetas(t);
                direction = [sind(theta).*cosd(phi);  sind(theta)*sind(phi) ; cosd(theta)];
                
                
                % Trace ray with isetlens
                wave = lens.get('wave');
                rays = rayC('origin',origin','direction', direction', 'waveIndex', 1, 'wave', wave);
                [~,~,out_point,out_dir]=lens.rtThroughLens(rays,1,'visualize',false);
                pass_trace = not(isnan(prod(out_point)));
                if(pass_trace)
                    alpha = entrancepupil_distance/(direction(3));
                    pointOnPupil = origin+alpha*direction;
                    pupilshape_trace(:,p,t,ph)=  pointOnPupil;
                end
                
            end
        end
    end
    
end

%% Step 1 : Fit exit pupil on axis
% At the onaxis position (p=1), there is no vignetting, and by construciton
% the pupil you see is the entrance pupil. The radius is estimated by
% finding the minimally bounding circle (using the toolbox)

p=1
Ptrace=pupilshape_trace(1:2,p,:);
Ptrace=Ptrace(1:2,:);

NaNCols = any(isnan(Ptrace));
Pnan = Ptrace(:,~NaNCols);
ZeroCols = any(Pnan(:,:)==[0;0]);
Pnan = Pnan(:,~ZeroCols);

[center0,radius0] = minboundcircle(Pnan(1,:)',Pnan(2,:)')

figure(1);clf; hold on;
viscircles(center0,radius0)
scatter(Ptrace(1,:),Ptrace(2,:),'.')


%% Step 2: Automatic estimation of the vignetting circles
% The automatic estimation algorithm tries to fit a circle that matches the
% curvature and position on opposite (vertical) sides of the pupil.

% Bottom
position_selection=2:8;
offaxis_distances=positions(position_selection);
offset=0.01;
stepsize_radius=0.001;
[radius_bottom,sensitivity_bottom]=findCuttingCircleEdge(pupilshape_trace(1:2,position_selection,:),offaxis_distances,"bottom",offset,stepsize_radius)

% Top
position_selection=5:8;
offaxis_distances=positions(position_selection);
offset=0.001;
stepsize_radius=0.01;
[radius_top,sensitivity_top]=findCuttingCircleEdge(pupilshape_trace(1:2,position_selection,:),offaxis_distances,"top",offset,stepsize_radius)

%% Verify automatic fits:


figure(1);clf; hold on;
for p=1:numel(positions)
    subplot(2,numel(positions)/2,p); hold on;
    Ptrace=pupilshape_trace(1:2,p,:);
    Ptrace=Ptrace(1:2,:);
    
    % Calculate offset of each circle
    offset_bottom=sensitivity_bottom*positions(p);
    offset_top=sensitivity_top*positions(p);
        
    % Draw circles
    viscircles(center0,radius0,'color','k')
    viscircles([0 offset_bottom],radius_bottom,'color','b')
    viscircles([0 offset_top],radius_top,'color','r')
    
    scatter(Ptrace(1,:),Ptrace(2,:),'.')
    xlim(0.5*[-1 1])
    ylim(0.5*[-1 1])
    pause(0.5);
    
    
end


%% Calculate pupil positions and radii
% To be used in 'checkRayPassLens'
% All circle intersections where done in the entrance pupil plane.
% Each circle is a projection of an actual pupil. Here I project the
% corresponding circles back to their respective plane where they are
% centered on the optical axis.

% Distance to entrance pupil is already known by construction
hx= entrancepupil_distance;

% Calculate radius of a pupil by projecting it back to its actual plane
% (where it is cented on the optical axis)
Rpupil_bottom = radius_bottom/(1-sensitivity_bottom)
Rpupil_top = radius_top/(1-sensitivity_top)


% Calculate positions of pupils relative to the input plane
hp_bottom=hx/(1-sensitivity_bottom)
hp_top=hx/(1-sensitivity_top)


% Information to be used for PBRT domain evaluation
radii = [radius0 Rpupil_bottom Rpupil_top]
pupil_distances = [hx, hp_bottom hp_top]


%% Second Verification (to check the ebove equations)
figure;

for p=1:numel(positions)    
    subplot(2,ceil(numel(positions)/2),p); hold on;
    
        
    % Plot traced pupil shape
    Ptrace=pupilshape_trace(1:2,p,:);
    Ptrace=Ptrace(1:2,:);
    scatter(Ptrace(1,:),Ptrace(2,:),'.')
    
    
    % Draw entrance pupil
    viscircles([0 0],radius0,'color','k')
    
    % Draw Bottom circle
    sensitivity = (1-hx/hp_bottom);
    dvignet=sensitivity*positions(p);
    projected_radius = abs(hx/hp_bottom)*Rpupil_bottom;
    viscircles([0 dvignet],projected_radius,'color','b')
    
    
    % Draw Top circle
    sensitivity = (1-hx/hp_top);
    dvignet=sensitivity*positions(p);
    projected_radius = abs(hx/hp_top)*Rpupil_top;
    viscircles([0 dvignet],projected_radius,'color','r')
       
    %axis equal
    ylim([-1 1])
    xlim(0.5*[-1 1])
    title(['x = ' num2str(positions(p))])
end


