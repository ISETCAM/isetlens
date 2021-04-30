function [figHdl, samps, endPoint, direction] = rtThroughLens(obj, rays, nLines, varargin)
% Rays at the entrance aperture are traced to the exit aperture
%
% Syntax:
%  lens.rtThroughLens(rays,nLines)
%
% Brief
%  Trace rays through a multi-element lens
%
% Inputs:
%  obj:    lensC 
%  rays:    rayC  
%  nLines: Specifies rendering options
%     This can be a structure with the fields
%       .spacing ('uniform' or 'random')
%       .numLines (how many lines)
%     This can be a number
%       <= 0 means don't draw the lines; any other positive
%     number describes how many to draw.
%
% Output:
%   figHdl:  Figure where the rays were drawn
%
% Description:
%  The initial rays from the scene are generated by a call to
%  lens.rtSourceToEntrance. That function takes a point input and generates
%  the ray positions and angles at the first lens surface. 
%
%  This routine traces the rays from the front surface through the
%  multi-element lens, computing the position and direction of the rays at
%  the final surface (exit aperture).
%
%  The recordOnFilm method (filmC), extends the lines to the film plane.
%
% TODO:  Simplify this code and add comments.
%        Especially, use the Wigner/Light field ideas
%
%  This should be handled, ultimately by a linear transform following
%  our analysis of the lens ABCD matrices and lightfields.  There is
%  bit of a nonlinearity, however, because there is an aperture in the
%  middle of the multi-element lens.
%
% AL, Vista team, 2013
%
% See also 
%   psfCameraC.estimatePSF, rayC.recordOnFilm. psfCameraC.draw, filmC.draw
%%
p = inputParser;
p.addParameter('visualize', true, @islogical);
p.parse(varargin{:});
vis = p.Results.visualize;
%% Ray trace calculation starts here
%
% The order of ray tracing is from furthest from film to film. This is
% also how the rays pass through the optics, but it is the opposite
% direction typically used in graphics software (e.g., PBRT).

% How many rays
nRays = rays.get('n rays');

% Index of refraction of prior medium.  Air.  Wavelength-independent
prevN = ones(nRays, 1);   

% For each surface element (lenses and apertures).
nSurfaces = obj.get('numels');
apertureCount = 0;    % We check that there is only 1 aperture

% Which sample rays to visualize
if ~isstruct(nLines),                     samps = randi(nRays,[nLines,1]);
elseif strcmp(nLines.spacing, 'uniform'), samps = round(linspace(1, nRays, nLines.numLines));
elseif strcmp(nLines.spacing,'random'),   samps = randi(nRays,[nLines.numLines,1]);
elseif strcmp(nLines.spacing,'midline'),  samps = rays.get('midline indices');
else,  error('Unknown spacing parameter %s\n',nLines.spacing);
end
if ~isempty(samps)
    rays.drawSamples = samps;
end

figHdl = [];

%% Draw through each surface of the lens
for lensEl = 1:nSurfaces
    
    % Get the surface data
    curEl = obj.surfaceArray(lensEl);
    curApSemiDiam = curEl.apertureD/2;
    
    % Calculate ray intersection position with lens element or aperture. In
    % the case of a 0 curvature, the direction does not change.
    %
    % This uses the vector form of Snell's Law, but that is a very
    % confusing calculation.  See notes.
    %
    % About Snell's law: http://en.wikipedia.org/wiki/Snell's_law
    if (curEl.sRadius ~= 0)
        % Calculation for a spherical lens surface
        
        % Figure out the center and radius
        repCenter = repmat(curEl.sCenter, [nRays 1]);
        repRadius = repmat(curEl.sRadius, [nRays 1]);

        % I think this step
        % calculates the line from the exit of previous surface to the next
        % surface. The current rays have an origin and a direction.  I
        % think these are calculated as a straight line that continues the
        % rays in the direction they are traveling.
        %
        % This stage calculates the distance to the next surface called 
        % intersectT. 
        %
        % Later in this function we apply Snell's law to get the new
        % direction of the ray as it exits the next surface.
        %
        % The intersectT calculation produces imaginary numbers for some
        % cases. It becomes imaginary if the extending the ray will never 
        % intersect with the sphere lens.
        %
        % Also the ray may intersect with the sphere but outside the
        % aperture. We delete these rays and the ones above.
        
        % Radicand: The value inside the radical symbol. 'Radical': the
        % square root symbol. Zheng will create a picture showing the
        % geometry of this calculation.
        radicand = dot(rays.direction, rays.origin - repCenter, 2).^2 - ...
            ( dot(rays.origin - repCenter, rays.origin - repCenter, 2)) + repRadius.^2;
        
        % intersectT is the distance from the ray origin to the next
        % surface. The reason of it becomes imaginary is because the
        % radicand is negative.
        if (curEl.sRadius < 0)
            intersectT = (-dot(rays.direction, rays.origin - repCenter, 2) + sqrt(radicand));
        else
            intersectT = (-dot(rays.direction, rays.origin - repCenter, 2) - sqrt(radicand));
        end
        
        % Figure out the new end point position
        endPoint = rays.endPoint(intersectT);
        % disp(['size rays' num2str(size(rays))])
        % If the ray falls of the circle of the lens OR it's outside of the aperture,
        % set rays outside of the aperture to NaN.
        outsideAperture = (imag(intersectT) ~=0) | (endPoint(:, 1).^2 + endPoint(:, 2).^2 >= curApSemiDiam^2);
        endPoint(outsideAperture, :) = NaN;
        prevN(outsideAperture)       = NaN;
        rays.removeDead(outsideAperture);

        
        % Update the drawing before we replace the origin and endpoints
        % rtVisualizeRays(obj,rays,nLines,endPoint,lensEl);
        if lensEl == 1 && ~isempty(samps)
            if vis
                [samps,figHdl] = raysVisualize(rays.origin,endPoint,'nLines',nLines,'surface',curEl);
            end
            % Set the axis numerical limits to make the lens visible
            thickness = obj.get('lens thickness');
            height    = obj.get('lens height');
            set(gca,'xlim',[-2*thickness 2]);
            set(gca,'ylim',[-1*height,height])
            grid on; hold on
            
        elseif ~isempty(samps) > 0
            if vis
                raysVisualize(rays.origin,endPoint,'nLines',nLines,'surface',curEl,'fig',figHdl,'samps',samps);
            end
            % Calculate direction vector compared to horiziontal axis (This
            % only works for 2D slice)
            direction=endPoint-rays.origin; 
            % Normalize direction
            % direction=direction/norm(direction);
            direction = direction ./ repmat(sqrt(sum(direction.^2, 2)), [1, size(direction, 2)]);
        end
        

        
        % Add this segment to the total distance
        rays.addDistance(intersectT.*prevN);
        
        % If a spherical surface, and this only works with spherical
        % lenses, apply Snell's law.  This determines the new ray
        % directions and origin
        %
        % N.B. There is no need to update the direction in the case of an
        % aperture. This section of code could become a function.
        % 
        %   rtSnell(rays, curEl, endPoint), or
        %   rayC.rtSnell(curEl, endPoint)
        %
        repCenter = repmat(curEl.sCenter, [nRays 1]);
        % Does the polarity of this vector matter? YES
        normalVec = endPoint - repCenter;  
        % Normalizes each row
        normalVec = normalVec ./ repmat(sqrt(sum(normalVec.*normalVec, 2)),[1 3]); 
        % This is the correct sign convention
        if (curEl.sRadius < 0), normalVec = -normalVec; end
        
        % Can this be managed by removeDead?
        % liveIndices = ~isnan(rays.waveIndex);
        liveIndices = rays.get('liveIndices');
        
        % Update samps. Only keep rays that still alive. (ZLY)
        samps = intersect(samps, find(liveIndices));
        
        % Index of refraction of the material in this surface.  This is
        % wavelength dependent.
        curN = ones(size(prevN));
        curN(liveIndices) = curEl.n(rays.waveIndex(liveIndices));  %deal with nans
        curN(~liveIndices) = NaN;
        
        % Snell's law accounts for the change in the index of refraction
        % ratios at surface boundary
        ratio = prevN./curN;
        
        % Vector form of Snell's Law
        c = -dot(normalVec, rays.direction, 2);
        repRatio = repmat(ratio, [1 3]);
        
        % Update the direction of the ray
        rays.origin = endPoint;
        
        % We used to plot phase-space
        % Maybe we should make this a separate function
        % Plot phase space right before the lens, before the rays are bent
        %         if (lensEl == 1 && nLines > 0)
        %             rays.plotPhaseSpace();  %this is before the change in position
        %         end
        
        % Use bsx for speed.
        % Simplify the line
        newVec = repRatio .* rays.direction + ...
            repmat((ratio.*c -sqrt(1 - ratio.^2 .* (1 - c.^2))), [1 3])  .* normalVec;
        rays.direction = newVec;
        rays.normalizeDir();
        rays.removeDead(any((imag(newVec) ~=0), 2)); % Remove imaginary dir rays

        % newVec2 = newVec./repmat(sqrt(sum(newVec.*newVec, 2)), [1 3]); %normalizes each row
        % vcNewGraphWin; plot(newVec(:),newVec2(:),'.');
        %
        %note: curN won't change if the surface is an aperture
        prevN = curN;
        
        % At the last surface, add the rays and store the light field
        if lensEl == nSurfaces
              intersectZ = repmat(curEl.sCenter(3), [nRays 1]);    % Thomas: this seemed to be missing?
            rays.aExitInt.XY = endPoint(:,1:2);  % only X-Y coords
            rays.aExitInt.Z  = intersectZ;       % aperture Z
            rays.aExitDir    = rays.direction;
        end
        

        
    elseif (curEl.sRadius == 0)
        % This is an aperture plane
        %
        % We should count whether there is more than one aperture plane.
        % There shouldn't be.
        
        % Should the code in here be updated with some of the function
        % calls, like rays.endPoint()? (BW)?
        intersectZ = repmat(curEl.sCenter(3), [nRays 1]);
        intersectT = (intersectZ - rays.origin(:, 3))./rays.direction(:, 3);
        repIntersectT = repmat(intersectT, [1 3]);
        endPoint = rays.origin + rays.direction .* repIntersectT;
        curApSemiDiam = min(curEl.apertureD, obj.apertureMiddleD)/2;
        
        % Set rays outside of the aperture to NaN
        outsideAperture = (endPoint(:, 1).^2 + endPoint(:, 2).^2) >= curApSemiDiam^2;
        endPoint(outsideAperture, :) = NaN;
        prevN(outsideAperture)       = NaN;
        rays.removeDead(outsideAperture);
        
        % Add this segment to the total distance.  We use this for
        % calculating the sum of the wavefronts for diffraction
        % calculations.
        rays.addDistance(intersectT.*prevN);
        
        % Store the rays for the light field calculation of the
        %   Front lens group | Aperture | Back lens group
        % There should only be one aperture in the lens model.
        if apertureCount, error('More than one aperture'); end
        rays.aMiddleInt.XY = 0;
        rays.aMiddleInt.XY = endPoint(:,1:2);  % only X-Y coords
        rays.aMiddleInt.Z  = intersectZ;       % aperture Z
        rays.aMiddleDir    = rays.direction;
        apertureCount = 1;   % Check that we never get here again!
        
        if lensEl == 1 && nLines > 0
            [samps,figHdl] = raysVisualize(rays.origin,endPoint,'nLines',nLines,'surface',curEl);
            hold on
        elseif isstruct(nLines) && nLines.numLines > 0 || isnumeric(nLines) && nLines > 0
            if vis
                raysVisualize(rays.origin,endPoint,'nLines',nLines,'surface',curEl,'fig',figHdl,'samps',samps);
            end
        end
        
        % HURB diffraction calculation
        if (obj.diffractionEnabled)
            obj.rtHURB(rays, endPoint, curApSemiDiam);
        end
    
    end
end

end
