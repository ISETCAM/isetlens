function obj = rtThroughLens(obj, rays, nLines)
% Rays at the entrance aperture are traced to the exit aperture
%
% Syntax:
%  lens.rtThroughLens(rays,nLines)
%
% Brief
%  Trace rays through a multi-element lens
%
% Inputs:
%  obj:    lens class
%  ray:    rayC  class
%  nLines: Specifies rendering options
%     This can be a structure with the fields
%       .spacing ('uniform' or 'random')
%       .numLines (how many lines)
%     This can be a number
%       <= 0 means don't draw the lines; any other positive
%     number describes how many to draw.
%
% Description:
%  The initial rays are generated by a call to
%  lens.rtSourceToEntrance, which takes a point input and generates
%  the ray positions and angles at the entrance aperture.  That
%  calculation is done without using any wavelength information
%
%  On return, the rays at the front aperture are changed to be the
%  position and direction of the rays at the exit aperture.
%
%  This should be handled, ultimately by a linear transform following
%  our analysis of the lens ABCD matrices and lightfields.  There is
%  bit of a nonlinearity, however, because there is an aperture in the
%  middle of the multi-element lens.
%
%  In that routine, one can ask that the lines be extended to the film
%  plane by setting a flag.  The flag adds a final surface in the film
%  plane to the surfaceArray
%
% TODO:  Simplify this code and add comments.
%        Especially, use the Wigner/Light field ideas
%
% AL, Vista team, 2013
%
% See also 
%   psfCameraC.estimatePSF

%% Ray trace calculation starts here
%
% The order is from furthest from film to film, which is also
% how the rays pass through the optics.

% How many rays
nRays = rays.get('n rays');
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

%% Draw through each surface of the lens
for lensEl = 1:nSurfaces
    
    % Get the surface data
    curEl = obj.surfaceArray(lensEl);
    curApSemiDiam = curEl.apertureD/2;
    
    % Calculate ray intersection position with lens element or
    % aperture. In the case of a 0 curvature, the direction
    % does not change.
    %
    % This uses the vector form of Snell's Law:
    % http://en.wikipedia.org/wiki/Snell's_law
    if (curEl.sRadius ~= 0)
        % This is a spherical element
        
        % Figure out the center and radius
        repCenter = repmat(curEl.sCenter, [nRays 1]);
        repRadius = repmat(curEl.sRadius, [nRays 1]);
        
        % Radicand from vector form of Snell's Law
        % <http://www.starkeffects.com/snells-law-vector.shtml>
        radicand = dot(rays.direction, rays.origin - repCenter, 2).^2 - ...
            ( dot(rays.origin - repCenter, rays.origin - repCenter, 2)) + repRadius.^2;
        
        % Calculate something about the ray angle with respect to the
        % current surface.  AL to figure this one out and put in a
        % book reference.
        if (curEl.sRadius < 0)
            intersectT = (-dot(rays.direction, rays.origin - repCenter, 2) + sqrt(radicand));
        else
            intersectT = (-dot(rays.direction, rays.origin - repCenter, 2) - sqrt(radicand));
        end
        
        % Test that intersectT is real.  Why are there imaginary
        % terms?  I think these are rays that do not make it through
        % the pathway.
        if (~isreal(intersectT(:)))
            fprintf('Imaginary values intersectT for lens element %d\n',lensEl);
        end
        
        % Figure out the new end point position
        endPoint = rays.endPoint(intersectT);
        
        % Update the drawing before we replace the origin and endpoints
        % rtVisualizeRays(obj,rays,nLines,endPoint,lensEl);
        if lensEl == 1 && ~isempty(samps)
            [samps,h] = raysVisualize(rays.origin,endPoint,'nLines',nLines,'surface',curEl);
            hold on
        elseif ~isempty(samps) > 0
            raysVisualize(rays.origin,endPoint,'nLines',nLines,'surface',curEl,'fig',h,'samps',samps);
        end
        
        % Set rays outside of the aperture to NaN
        outsideAperture = endPoint(:, 1).^2 + endPoint(:, 2).^2 >= curApSemiDiam^2;
        endPoint(outsideAperture, :) = NaN;
        prevN(outsideAperture)       = NaN;
        rays.removeDead(outsideAperture);
        
        % Add this segment to the total distance
        rays.addDistance(intersectT.*prevN);
        
        % If a spherical surface, apply Snell's law to determine the new ray
        % directions and origin
        % N.B. No need to update the direction in the case of an aperture.
        % Most of this section could become a function.  It could be
        
        repCenter = repmat(curEl.sCenter, [nRays 1]);
        normalVec = endPoint - repCenter;  %does the polarity of this vector matter? YES
        normalVec = normalVec./repmat(sqrt(sum(normalVec.*normalVec, 2)),[1 3]); %normalizes each row
        
        %This is the correct sign convention
        if (curEl.sRadius < 0), normalVec = -normalVec; end
        
        % The function could be called here
        % rtSnell(rays,curEl,normalVec,prevN)
        
        % Can this be managed by removeDead?
        %liveIndices = ~isnan(rays.waveIndex);
        liveIndices = rays.get('liveIndices');
        curN = ones(size(prevN));
        curN(liveIndices) = curEl.n(rays.waveIndex(liveIndices));  %deal with nans
        curN(~liveIndices) = NaN;
        
        % Snell's law accounts for the change in the index of refraction
        % ratios at surface boundary
        ratio = prevN./curN;
        
        % Vector form of Snell's Law
        c = -dot(normalVec, rays.direction, 2);
        repRatio = repmat(ratio, [1 3]);
        
        %update the direction of the ray
        rays.origin = endPoint;
        
        %We used to plot phase-space
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
        
        % newVec2 = newVec./repmat(sqrt(sum(newVec.*newVec, 2)), [1 3]); %normalizes each row
        % vcNewGraphWin; plot(newVec(:),newVec2(:),'.');
        %
        %note: curN won't change if the aperture is the overall lens aperture
        prevN = curN;
        
        % At the last surface, add the rays and store the light field
        if lensEl == nSurfaces
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
            [samps,h] = raysVisualize(rays.origin,endPoint,'nLines',nLines,'surface',curEl);
            hold on
        elseif nLines > 0
            raysVisualize(rays.origin,endPoint,'nLines',nLines,'surface',curEl,'fig',h,'samps',samps);
        end
        
        % HURB diffraction calculation
        if (obj.diffractionEnabled)
            obj.rtHURB(rays, endPoint, curApSemiDiam);
        end
    
    end
   
    
end

end
