function fileRead(obj, fullFileName, varargin)
% @lens method to reads a PBRT lens file
%
% Syntax:
%   lens.fileRead(fullFileName, varargin)
%
% Input:
%   The name of a PBRT lens file
%
% Outputs
%   The lens class (obj) is modified so that its parameters match the
%   contents of the lens file
%
% Optional key/value pairs:
%   'units' - Set the spatial units
%       By default, lenses are specified in millimeters.  If 'm' or 'um' is
%       sent in, the numbers in the lens file are scaled to bring the units
%       into 'mm'.  Thus, if 'm' is sent in, the values are multiplied by
%       1000, and if 'um' are sent in the values are divided by 1000.
%
% Description:
%  Data from a lens.dat file are read in and converted to the fields of a
%  lens object. The read is managed by fileRead, and the conversion from
%  the data stored in the lens.dat file to the values in the lens class are
%  managed by the method 'elementsSet'. This converts the vector of lens
%  and aperture values in the file into the lens.surfaceArray parameters.
%
%  The lens class parameters are surface Offset (mm), sRadius (mm),
%  sAperture (mm), sN (index of refraction).
%
%  The lens surfaces are ordered from scene to sensor (top to bottom
%  of the rows in the lens text file).  In the JSON case, the surfaces
%  are listed in that same order.
%
% AL/TL VISTASOFT, Copyright 2014

%% Arrange parameters
p = inputParser;
p.addRequired('fullFileName',@(x)(exist(x,'file')));
p.addParameter('units','mm',@(x)(ismember(x,{'um','mm','m'})));
p.parse(fullFileName,varargin{:});

unitScale = p.Results.units;
switch unitScale
    case 'um'
        % Values are in microns, so divided by 1000 to bring to millimeters
        unitScale = 1e-3;
    case 'mm'
        unitScale = 1;
    case 'm'
        % Values are in meters, so x 1000 to bring to millimeters
        unitScale = 1e3;
    otherwise
        error('Unknown spatial scale');
end

fileFormat = 'txt';   % This wil go away after debugging
[~,~,e] = fileparts(fullFileName);
if strcmp(e,'.json'), fileFormat = 'json';
elseif strcmp(e,'.txt'), fileFormat = 'txt';
end

switch fileFormat
    case 'txt'
        %% Open the lens file
        fid = fopen(fullFileName);
        if fid < 0, error('File not found %s\n',fullFileName); end
        
        % Read each of the lens and close the file
        import = textscan(fid, '%s%s%s%s', 'delimiter' , '\t');
        fclose(fid);
        
        % Read the focal length of the lens. Search for the first non-commented
        % line in the first column.
        id = find(isnan(str2double(import{1})) == false,1,'first');
        obj.focalLength = str2double(import{1}(id))*unitScale;
        
        % First find the start of the lens line, marked "#   radius"
        firstColumn = import{1};
        continueRead = true;
        dStart = 1;   % Row where the data entries begin
        while(continueRead && dStart <= length(firstColumn))
            compare = regexp(firstColumn(dStart), 'radius');
            if(~(isempty(compare{1})))
                continueRead = false;
            end
            dStart = dStart+1;
        end
        
        % Now that we know which line the numerical data begins at, we can read
        % each column and save the data.
        radius = str2double(import{1});
        radius = radius(dStart:length(firstColumn)) * unitScale;
        if sum(isnan(radius)) > 0
            warning('Error reading lens file radius');
            lst = find(isnan(radius));
            fprintf('Bad indices %d\n',lst);
        end
        
        % Read in "Axpos," which is the distance from the current surface to the
        % next surface. (We call this "offset.") The offset denotes the distance
        % between the current surface and the previous one. In the PBRT file, there
        % is a "0" at the end of the column because (1) PBRT reads the data in
        % reverse and (2) there isn't a lens before the first one. For our CISET
        % ray tracing convention, we go from the scene to the sensor, so we must
        % move the zero to the beginning of the column but keep the rest of the
        % data in the same order.
        offset = str2double(import{2});
        offset = offset(dStart:length(firstColumn));
        offset = [0; offset(1:(end-1))]; % Shift to account for different convention
        offset = offset*unitScale;
        if sum(isnan(offset)) > 0
            warning('Error reading lens file offset');
            lst = find(isnan(offset));
            fprintf('Bad indices %d\n',lst);
        end
        
        % Read in N, the index of refraction.
        N = str2double(import{3});
        N = N(dStart:length(firstColumn));
        
        % Read in diameter of the aperture.
        aperture = str2double(import{4});
        aperture = aperture(dStart:length(firstColumn));
        aperture = aperture*unitScale;
        if sum(isnan(aperture)) > 0
            warning('Error reading lens file aperture');
            lst = find(isnan(aperture));
            fprintf('Bad indices %d\n',lst);
        end
        
        % Modify the object with the data we read
        obj.elementsSet(offset, radius, aperture, N);
        
        % Figure out which is the aperture/diaphragm by looking at the radius.
        % When the spherical radius is 0, that means the object is an aperture.
        lst = find(radius == 0);
        if length(lst) > 1,         error('Multiple non-refractive elements %i\n',lst);
        elseif length(lst) == 1,    obj.apertureIndex(lst);
        else,                       error('No non-refractive (aperture/diaphragm) element found');
        end
    case 'json'
        % Read the JSON file with the lens definition
        %
        lensData  = jsonread(fullFileName);
        obj.fullFileName = fullFileName;
        obj.name = lensData.name;
        obj.description = lensData.description;
        
        %{
        offset = str2double(import{2});
        offset = offset(dStart:length(firstColumn));
        offset = [0; offset(1:(end-1))]; % Shift to account for different convention
        offset = offset*unitScale;
        if sum(isnan(offset)) > 0
            warning('Error reading lens file offset');
            lst = find(isnan(offset));
            fprintf('Bad indices %d\n',lst);
        end
        %}
        
        % For each surface transform the data into the lensC format
        jSurfaces = lensData.surfaces;
        nSurfaces = numel(jSurfaces);
        sIOR = zeros(nSurfaces,1);
        sRadius = sIOR; sOffset = sIOR; sApertureDiameter = sIOR;
        for ii =1:nSurfaces 
            sIOR(ii)    = jSurfaces(ii).ior;
            sRadius(ii) = jSurfaces(ii).radius;   % Radius of curvature
            sApertureDiameter(ii) = 2*jSurfaces(ii).semi_aperture;
            sOffset(ii) = jSurfaces(ii).thickness;
        end
        sOffset = [sOffset(end); sOffset(1:(end-1))]*unitScale;
        
        obj.elementsSet(sOffset, sRadius, sApertureDiameter, sIOR)

        
        % To make this work with current isetlens, we need to convert
        % the parameters
        
        % Take the lensData and fill in the slots we used in the txt
        % format.
        % obj.txtFormat();
        
        % Take the lensData and 
        
    otherwise
        error('Unknown file format %s\n',fileFormat);
end

end


