function [onsets, offsets] = findSyncClickOnsets(audio, fs, threshold, pulse_time, plot_onsets)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% findSyncClickOnsets: Find synchronization "clicks" in audio data
% usage: onsets = findSyncClickOnsets(audio)
% usage: onsets = findSyncClickOnsets(audio, threshold, debounce_time)
%
% where,
%    audio is a 1D vector representing an audio signal, or a file path to 
%       an audio file
%    fs is the sampling rate of the audio. If audio is a file path, this
%       may be left as an empty array to use the sampling rate recorded in 
%       the audio file
%    threshold is a threshold defining the minimum amplitude for a sync 
%       click in arbitrary audio input units
%    pulse_time is the time between the "on" click and the "off" click
%    onsets is a 1D vector of sync click onsets, in units of audio samples
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
    fs double = []
    threshold (1, 1) double = 1.5
    pulse_time (1, 1) double = 0.08
    plot_onsets (1, 1) logical = false
end

if ischar(audio)
    % Assume this is a path - load the audio
    [audio, fs_loaded] = audioread(audio);
    if isempty(fs)
        fs = fs_loaded;
    end
end

% Empirically determined delay between relay deactivation and click sound
pulse_delay = 0.0035;
% Adjust pulse time
pulse_time = pulse_time + pulse_delay;
% Tolerance for variation in relay turn-off time
pulse_tolerance = 0.03 * pulse_time;
% Convert pulse times to sampels
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

if plot_onsets
    figure; 
    ax = axes();
    plot(ax, audio); 
    hold(ax, 'on');
    for onset = onsets
        plot(ax, [onset, onset], ax.YLim, 'g');
    end
    for offset = offsets
        plot(ax, [offset, offset], ax.YLim, 'r');
    end
    hold(ax, 'off');
end