%% Images for a typical automotive lens
%
% Also includes some autofocusing calculation
%
%

%%
ieInit

%% Create lens 
%
% Also set the number of sample rays to use for the calculation.

lens = lensC('filename','wide.56deg.6.0mm.json');
lens.apertureSample = [601 601];          % Number of samples at first lens

% lens.draw; grid on; title('')

%%  Set up point, lens, film

[pt, ~, film] = ilInitPLF;
pt{1}     = [0, 0, -10^6];  % For a point that is far away
film.size = [0.05 0.05];    % A small bit of film, in millimeters

%% The film is put at the focal length
camera = psfCameraC('lens',lens,'point source',pt,'film',film);

% The auto focus puts the film at the focal length.
% {
camera.autofocus(550,'nm');
%}

%{
% You could set the value differently, if you like.
camera.set('film position',[0 0 2.8]);
%}

fprintf('Film distance:\t%f\nFocal length:\t%f\n',...
    camera.get('film distance'),lens.get('focal length'));

%% Not sure how to control the quality here

nLines = 100;  % Do not draw the rays if 0.
jitter = true;
camera.estimatePSF(nLines,jitter);

% Set x axis to 1 millimeter beyond the film and 15 mm in front of the
% lens
xFilm = camera.get('film distance');
yFilm = get(gca,'ylim');
hLine = line([xFilm xFilm],yFilm,'LineStyle',':','Color',[0.2 0 0.5]);
set(gca,'xlim',[-15 (camera.get('film distance') + 1)]);

%% The oi illuminance level is arbitrary

oi = camera.oiCreate('mean illuminance',5);
oiWindow(oi);

oiPlot(oi,'illuminance mesh linear');

%% Approximate the size of the point image on the sensor

% This is the illuminance image
ill = oiGet(oi,'illuminance');

% Find all the points that are at least 10 percent the amplitude of the
% peak illuminance
mx = max(ill(:));
ill(ill < 0.1*mx)  = 0;
ill(ill >= 0.1*mx) = 1;

% Find the area of those points
sampleSpacing = oiGet(oi,'sample spacing','um');
psArea = sum(ill(:))*sampleSpacing(1);   % This is the pointspread area in meters

% If they are roughly circular, then we can estimate the diameter this way
%
% circleArea = pi*radiusSquared
%
% So, putting psArea into circleArea the diameter would be
%
psDiameter = 2*(psArea/pi)^0.5;   % Diameter in microns
fprintf('\nPoint spread diameter %f um\n',psDiameter);

%% Render for a sensor with big pixels

sensor = sensorCreate('MT9V024');       % This is a 6 um sensor
sensor = sensorSetSizeToFOV(sensor,2);  % Make it small
sensor = sensorCompute(sensor,oi);

% Bring up the window, with the display intensity scaled to max
sensorWindow(sensor,'scale',1);

%%


