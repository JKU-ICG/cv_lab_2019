% --- Computer Vision Toolbox: Panorama Stitching Tutorial ---
clear; close all; clc; % clean up!
% for details see: https://de.mathworks.com/help/vision/examples/feature-based-panoramic-image-stitching.html

%% Load images.
% if you don't want to download the science park dataset you can use
% Matlab's example images: 
%   buildingDir = fullfile(toolboxdir('vision'), 'visiondata', 'building');
buildingDir = 'data\panorama\science_park';
buildingScene = imageDatastore(buildingDir); % datastore keeps all images in a folder

% Display images to be stitched
figure(1); montage(buildingScene.Files);

% Read the first image from the image set.
I = readimage(buildingScene, 1);

%% Initialize features for I(1)
grayImage = rgb2gray(I);
points = detectSURFFeatures(grayImage);
[features, points] = extractFeatures(grayImage, points);
figure(2); % display
set(gcf, 'Color', 'white' )
imshow(grayImage); hold on;
plot( points.selectStrongest(25) ); 
title( 'strongest SURF features image 1' );


% Initialize all the transforms to the identity matrix. Note that the
% projective transform is used here because the building images are fairly
% close to the camera. Had the scene been captured from a further distance,
% an affine transform would suffice.
numImages = numel(buildingScene.Files);
clear tforms;
tforms(1) = projective2d(eye(3));

% Initialize variable to hold image sizes.
imageSize = zeros(numImages,2);
imageSize(1,:) = size(grayImage);

%% Iterate over remaining image pairs
for n = 2:numImages
    
    % Store points and features for I(n-1).
    pointsPrevious = points;
    featuresPrevious = features;
    grayImagePrev = grayImage;
        
    % Read I(n).
    I = readimage(buildingScene, n);
    
    % Convert image to grayscale.
    grayImage = rgb2gray(I);    
    
    % Save image size.
    imageSize(n,:) = size(grayImage);
    
    % Detect and extract SURF features for I(n).
    points = detectSURFFeatures(grayImage);    
    [features, points] = extractFeatures(grayImage, points);
    figure(1+n); % display
    set(gcf, 'Color', 'white' )
    imshow(grayImage); hold on;
    plot( points.selectStrongest(25) ); 
    title( ['strongest SURF features image ' num2str(n)] );
  
    % Find correspondences between I(n) and I(n-1).
    indexPairs = matchFeatures(features, featuresPrevious, 'Unique', false);
       
    matchedPoints = points(indexPairs(:,1), :);
    matchedPointsPrev = pointsPrevious(indexPairs(:,2), :); 
    
    % Display inbetween:
    figure(10+n); clf;
    showMatchedFeatures(grayImage, grayImagePrev, matchedPoints, matchedPointsPrev,'montage');
    title( [ 'Tracked Features of images ' num2str(n-1) ' and ' num2str(n) ]);
    drawnow;
    
    % Estimate the transformation between I(n) and I(n-1).
    tforms(n) = estimateGeometricTransform(matchedPoints, matchedPointsPrev,...
        'projective', 'Confidence', 90, 'MaxNumTrials', 2000, 'MaxDistance', 2 );
    
    % Compute T(n) * T(n-1) * ... * T(1)
    tforms(n).T = tforms(n).T * tforms(n-1).T; 
end
%%

xlim = zeros( numImages, 2 ); ylim = xlim;
% Compute the output limits  for each transform
for i = 1:numImages           
    [xlim(i,:), ylim(i,:)] = outputLimits(tforms(i), [1 imageSize(i,2)], [1 imageSize(i,1)]);    
end


% let's assume the images are sorted
centerIdx = floor((numel(tforms)+1)/2);
centerImageIdx = (centerIdx);

Tinv = invert(tforms(centerImageIdx));

for i = 1:numImages    
    tforms(i).T = tforms(i).T * Tinv.T;
end

for i = 1:numImages           
    [xlim(i,:), ylim(i,:)] = outputLimits(tforms(i), [1 imageSize(i,2)], [1 imageSize(i,1)]);
end

maxImageSize = max(imageSize);

% Find the minimum and maximum output limits 
xMin = min([1; xlim(:)]);
xMax = max([maxImageSize(2); xlim(:)]);

yMin = min([1; ylim(:)]);
yMax = max([maxImageSize(1); ylim(:)]);

% Width and height of panorama.
width  = round(xMax - xMin);
height = round(yMax - yMin);

% due to perspective warping limits can get large and thus the panorama
% width, height. Thus, limit:
width  = min( width, maxImageSize(2)*numImages/2 );
height = min( height, maxImageSize(1)*numImages/2 );


% Initialize the "empty" panorama.
panorama = zeros([height width 3], 'like', I);

blender = vision.AlphaBlender('Operation', 'Binary mask', ...
    'MaskSource', 'Input port');  

% Create a 2-D spatial reference object defining the size of the panorama.
xLimits = [xMin xMax];
yLimits = [yMin yMax];
panoramaView = imref2d([height width], xLimits, yLimits);

% Create the panorama.
for i = 1:numImages
    
    I = readimage(buildingScene, i); 
    
    % Transform I into the panorama.
    warpedImage = imwarp(I, tforms(i), 'OutputView', panoramaView);
                  
    % Generate a binary mask. 
    mask = true(size(I,1),size(I,2));
    mask = imwarp(mask, tforms(i), 'OutputView', panoramaView);
    
    % Overlay the warpedImage onto the panorama.
    panorama = step(blender, panorama, warpedImage, mask);
end

figure(15)
imshow(panorama); title( 'panorama' );
if ~exist( 'results', 'dir' ), mkdir( 'results' ); end;
imwrite( panorama, "results/panorama.jpg"  );