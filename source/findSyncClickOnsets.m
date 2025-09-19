function [onsets, offsets, num_samples] = findSyncClickOnsets(audio, threshold, pulse_time, options)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% findSyncClickOnsets: Find synchronization "clicks" in audio data
% usage: onsets = findSyncClickOnsets(audio)
% usage: onsets = findSyncClickOnsets(audio, threshold, debounce_time)
%
% where,
%    audio is a 1D vector representing an audio signal, or a file path to 
%       an audio file
%    threshold is a threshold defining the minimum amplitude for a sync 
%       click in arbitrary audio input units
%    pulse_time is the time between the "on" click and the "off" click
%    Name/Value pairs may include:
%       SamplingRate: the sampling rate of the audio. If audio is a file 
%           path, this may be left as an empty array (default) to use the 
%           sampling rate recorded in the audio file.
%       Channel: which channel to use if the audio contains more than one.
%           Default is 1.
%       PlotOnsets: display detection data in a plot. Default is false.
%    onsets is a 1D vector of sync click onsets, in units of audio samples
%    offsets is a 1D vector of sync click offsets, in units of audio 
%       samples
%    num_samples is the number of audio samples in the file
%
% For post-hoc audio/video synchronization, a simultaneous light/sound 
%   signal is recorded such that light onsets and "click" onsets can be
%   matched up. This setup provides a click both at the start of the sync
%   light and at the end. The onset click is the most accurage, and should
%   coincide with the light pulse on the order of nanoseconds. The off 
%   click may be less well matched with the light offset, so it should not
%   be used for syncing, but can be used to verify that an onset click is
%   really an onset click.
% This function takes a vector of audio values, and identifies the start
%   times of any and all recorded synchronization clicks.
%
% See also:
%
% Version: 1.0
% Author:  Brian Kardon
% Email:   bmk27=cornell*org, brian*kardon=google*com
% Real_email = regexprep(Email,{'=','*'},{'@','.'})
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
arguments
    audio
    threshold (1, 1) double = 0.01
    pulse_time (1, 1) double = 0.08
    options.SamplingRate double = []
    options.Channel (1, 1) double = 1
    options.PlotOnsets (1, 1) logical = false
end

fs = options.SamplingRate;

if ischar(audio)
    % Assume this is a path - load the audio
    [audio, fs_loaded] = audioread(audio);
    if isempty(fs)
        fs = fs_loaded;
    end
end

if size(audio, 2) > 1
    % Multi-channel audio, select one channel
    audio = audio(:, options.Channel);
end

% Calculate number of audio samples in file or vector
num_samples = length(audio);

% Empirically determined delay between relay deactivation and click sound
pulse_delay = 0.0035;
% Adjust pulse time
pulse_time = pulse_time + pulse_delay;
% Tolerance for variation in relay turn-off time
pulse_tolerance = 0.03 * pulse_time;
% Convert pulse times to samples
pulse_samples = pulse_time * fs;
pulse_tolerance_samples = pulse_tolerance * fs;
% Debounce signal such that any repeated onsets spaced closer than half the\
%   pulse time are ignored.
debounce_time = pulse_time / 2;
% Convert debounce time to audio samples
debounce_samples = debounce_time * fs;

click_ons = find(abs(audio) > threshold);

click_starts = [];

% In case there was an onset right before the start of the file
debounce_start = 0;

while true
    % Eliminate any following onsets that are within the debounce time
    click_ons(click_ons < (debounce_start + debounce_samples)) = [];
    % Stop loop if we're out of onsets
    if isempty(click_ons)
        break;
    end
    % Record next onset
    click_starts(end+1) = click_ons(1); %#ok<*AGROW>
    % Reset debounce time
    debounce_start = click_ons(1);
end

onsets = [];
offsets = [];

% Look for onset/offset click pairs in click_starts. They only count as a
%   pair if they are separated within tolerance by the given pulse time.
for k = 1:length(click_starts)-1
    separation = click_starts(k+1) - click_starts(k);
    if abs(separation - pulse_samples) < pulse_tolerance_samples
        % This is a pulse on/off pair of clicks
        onsets(end+1) = click_starts(k);
        offsets(end+1) = click_starts(k+1);
    end
end

if options.PlotOnsets
    figure; 
    ax = axes();
    plot(ax, (1:length(audio)) / fs, audio, 'k');
    hold(ax, 'on');
    for onset = onsets
        plot(ax, onset/fs, 0, 'g*');
    end
    for offset = offsets
        plot(ax, offset/fs, 0, 'r*');
    end
    xlabel('time (s)');
    hold(ax, 'off');
end