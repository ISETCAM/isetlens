function [OptSyst] = bbmComputeOptSyst(obj,varargin)
% Get the Optical System structure generated by Michael's script
%
%INPUT
%   obj: lens object of SCENE3D
%  varargin {1}: refractive index of object space  [n_ob]
%  varargin {2}: refractive index of object space  [n_im]
%
%OUTPUT
%   OptSyst= optical System structure 
%
% It is useful to use other function and to get the value to append to
% Black Box Model 
%
%  OptSys = lens.bbmComputeOptSyst ()
%    or
%  OptSys = lens.bbmComputeOptSyst (n_ob,n_im)
%
%
% MP Vistasoft 2014

%% GET RELEVANT PARAMETERs for the COMPUTATION

unit = 'mm'; %unit
wave = obj.wave*1e-6; % in mm
nw = length(wave); %num wavelength

nelem=length(obj.surfaceArray);

%Initialize some vector
N=ones(nw,nelem); 

%Useful parameter
inD=1;

%% Get the parameter to build the Optical System
 
%USING SUBTYPE
for ni=1:nelem
    %Get the structure
    S=obj.surfaceArray(ni);
    switch S.subtype
        case {'diaphragm';'diaphr'}
            surftype{ni} = 'diaphragm';  
            if (S.apertureD == obj.apertureMiddleD) %Check if the aperture size is changed
                Diam(ni) = S.apertureD; %aperture diameter
            else
                Diam(ni)=obj.apertureMiddleD; %set aperture change
            end
            %save indices of the aperture
            indDiaph(inD)=ni;
            inD=inD+1;

            if ni>1
                N(:,ni)=N(:,ni-1); %refractive indices
           end
        case {'refractive','refr','spherical'}
            surftype{ni}='refr';
            N(:,ni)=S.n';           % refractive indices                
            Diam(ni)=S.apertureD;   % aperture diameter
        otherwise
            error (['NOT VALID ',S.subtype,' as surface subtype'])
    end
    Radius(ni)=S.sRadius; %radius of curvature
    posZ(ni)=S.get('zintercept');
    %% OTHER FIELDs
    % conicConstant (conical parameter)
    
end


 
%OLD VERSION: diaphragm was recognized as the refractive surface with the
%refrctive index equal to zero

% for ni=1:nelem
%     %Get the structure
%     S=obj.surfaceArray(ni);
%     if all(S.n==0)
%         surftype{ni}='diaphragm';  
%         if (S.apertureD==obj.apertureMiddleD) %Check if the aperture size is changed
%             Diam(ni)=S.apertureD; %aperture diameter
%         else
%             Diam(ni)=obj.apertureMiddleD; %set aperture change
%         end
%         %save indices of the aperture
%         indDiaph(inD)=ni;
%         inD=inD+1;
% 
%         if ni>1
%             N(:,ni)=N(:,ni-1); %refractive indices
%        end
%     else
%         surftype{ni}='refr';
%         N(:,ni)=S.n';           %refractive indices                
%         Diam(ni)=S.apertureD; %aperture diameter
%     end
%     Radius(ni)=S.sRadius; %radius of curvature
%     posZ(ni)=S.get('zintercept');
%     %% OTHER FIELDs
%     %conicConstant (conical parameter)
%     
% end

% Set new origin as the First Surface
PosZ=posZ-posZ(1);

%% Build several surface
for k=1:length(Radius)
    R(k)=Radius(k);
    z_pos(k)=PosZ(k);
    n(:,k)=N(:,k);
    diam(k)=Diam(k);
    switch surftype{k}
        case {'refr'}          
            surf{k}=paraxCreateSurface(z_pos(k),diam(k),unit,wave,surftype{k},R(k),n(:,k));
        case {'diaphragm','diaph'}
            surf{k}=paraxCreateSurface(z_pos(k),diam(k),unit,wave,surftype{k});
        case {'film'}
    end
end


%% CREATE OPTICAL SYSTEM and (possibly) IMAGING SYSTEM and psfCamera 
if nargin>1    
    switch varargin{1}
        case {'all'}
            psfFlag=1; %YES psfCamera object to compute
            lens0=obj;            
            pSource=varargin{2}; %get point source
            film0=varargin{3};
            if nargin >4
                n_ob=varargin{4};n_im=varargin{5};
            else
                n_ob=1; n_im=1;
            end
        otherwise                   
            n_ob=varargin{1};
            n_im=varargin{2};
    end
else            
    n_ob=1; n_im=1;
end
[OptSyst] = paraxCreateOptSyst(surf,n_ob,n_im,unit,wave);

%% END