function [onsets, offsets, num_frames] = findSyncFlashOnsets(video, ROI, threshold, pulse_time, options)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% findSyncClickOnsets: Find synchronization "clicks" in audio data
% usage: onsets = findSyncFlashOnsets(audio, ROI)
% usage: onsets = findSyncFlashOnsets(audio, ROI, threshold, debounce_time)
%
% where,
%    video is a 4D vector (h x w x c x n) representing a video signal
%    ROI is a 1x4 vector representing the ROI in which to look for flashes.
%       It should be in the form [x, y, w, h] where x and y are the 
%       coordinates of the upper left corner of the ROI, and w and h are 
%       the dimensions of the ROI. If left as an empty list (default), the
%       entire video will be used
%    threshold is a threshold defining the minimum amplitude for a sync 
%       click in arbitrary audio input units
%    pulse_time is the time between the "on" click and the "off" click
%    Name/Value pairs may include:
%       FrameRate: the frame rate of the video. Default is 25
%       PlotOnsets: display detection data in a plot. Default is false.
%       MedianWindow: Window to use for a moving de-median filter for the 
%           video intensity before thresholding. Default is [], which means
%           do not de-median the intensity.
%    onsets is a 1D vector of sync flash onsets, in units of frames
%    offsets is a 1D vector of sync flash offsets, in units of frames
%    num_frames is the number of frames in the video
%
% For post-hoc audio/video synchronization, a simultaneous light/sound 
%   signal is recorded such that light onsets and "click" onsets can be
%   matched up.
% This function takes an array representing video data, and identifies the 
%   start times of any and all recorded synchronization flashes.
%
% See also:
%
% Version: 1.0
% Author:  Brian Kardon
% Email:   bmk27=cornell*org, brian*kardon=google*com
% Real_email = regexprep(Email,{'=','*'},{'@','.'})
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
arguments
    video
    ROI double = []
    threshold (1, 1) double = 1.5
    pulse_time (1, 1) double = 0.08
    options.FrameRate double = 25
    options.PlotOnsets (1, 1) logical = false
    options.MedianWindow double = []
end

fs = options.FrameRate;

if ischar(video)
    % Assume this is a file path to a video - load it
    video = fastVideoReader(video, [], [], ROI);
    ROI = [];
end

if ~isempty(ROI)
    % If user provides a ROI, crop the video here
    x0 = ROI(1);
    y0 = ROI(2);
    x1 = x0 + ROI(3);
    y1 = y0 + ROI(4);
    video = video(y0:y1, x0:x1, :, :);
end

% Calculate the # of frames in the video
num_frames = size(video, 4);

% Average the video across space and color, leaving a 1D intensity time series
intensity = squeeze(mean(video, [1, 2, 3]));

% De-median intensity if requested
if ~isempty(options.MedianWindow)
    intensity = intensity - movmedian(intensity, options.MedianWindow);
end

if options.PlotOnsets
    figure; 
    ax = axes();
    plot(ax, (1:length(intensity)) / fs, intensity, 'k');
    ax.YLim = [0, 255];
    ax.YLimMode = 'manual';
end

% Empirically determined delay between relay deactivation and click sound
pulse_delay = 0.0;
% Adjust pulse time
pulse_time = pulse_time + pulse_delay;
% Tolerance for variation in relay turn-off time
pulse_tolerance = 0.08 * pulse_time;
pulse_tolerance_samples = max([2, pulse_tolerance * fs]);
% Convert pulse times to samples (frames)
pulse_samples = pulse_time * fs;
% Debounce signal such that any repeated onsets spaced closer than half the\
%   pulse time are ignored.
debounce_time = pulse_time / 2;
% Convert debounce time to audio samples
debounce_samples = debounce_time * fs;

flash_rising_edges = find(diff(abs(intensity) > threshold)>0);
flash_starts = [];

% In case there was an flash start right before the start of the file
debounce_start = 0;

while true
    % Eliminate any following rising edges that are within the debounce time
    flash_rising_edges(flash_rising_edges < (debounce_start + debounce_samples)) = [];
    % Stop loop if we're out of onsets
    if isempty(flash_rising_edges)
        break;
    end
    % Record next flash start
    flash_starts(end+1) = flash_rising_edges(1); %#ok<*AGROW>
    % Reset debounce time
    debounce_start = flash_rising_edges(1);
end

flash_falling_edges = find(diff(abs(intensity) > threshold) < 0);
flash_ends = [];

% In case there was an flash start right before the start of the file
debounce_start = 0;

while true
    % Eliminate any following falling edges that are within the debounce time
    flash_falling_edges(flash_falling_edges < (debounce_start + debounce_samples)) = [];
    % Stop loop if we're out of onsets
    if isempty(flash_falling_edges)
        break;
    end
    % Record next flash end
    flash_ends(end+1) = flash_falling_edges(1); %#ok<*AGROW>
    % Reset debounce time
    debounce_start = flash_falling_edges(1);
end

onsets = [];
offsets = [];

% Look for onset/offset flash pairs. They only count as a pair if they are 
%   separated within tolerance by the given pulse time.
for k = 1:length(flash_starts)
    % Possible flash ends must not have any other flash starts before them
    if k+1 <= length(flash_starts)
        possible_flash_ends = flash_ends(flash_ends < flash_starts(k+1));
    else
        possible_flash_ends = flash_ends;
    end
    % Calculate when this flash should end
    predicted_flash_end = flash_starts(k) + pulse_samples;
    % See if any flash_ends are within tolerance of the predicted time
    matching_ends = possible_flash_ends(floor(predicted_flash_end - pulse_tolerance_samples) <= possible_flash_ends & possible_flash_ends <= ceil(predicted_flash_end + pulse_tolerance_samples));
    % How many ends matched?
    if length(matching_ends) == 1 %#ok<*ISCL>
        % One end matched - looks like a valid pulse
        onsets(end+1) = flash_starts(k)+1;
        offsets(end+1) = matching_ends;
    elseif length(matching_ends) > 1
        % More than one end matched? pick the best candidate

    else
        % Zero ends matched. Could be because the end was off the end of the file
    end
end

if options.PlotOnsets
    hold(ax, 'on');
    for onset = onsets
        plot(ax, onset/fs, intensity(onset), 'g*');
    end
    for offset = offsets
        plot(ax, offset/fs, intensity(offset), 'r*');
    end
    xlabel('time (s)');
    hold(ax, 'off');
end