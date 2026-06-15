function [onsets, offsets, num_samples, fs] = findSyncClickOnsets(audio, threshold, pulse_time, options)
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
%    pulse_time is the approximate time between the "on" click and the 
%       "off" click
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
    options.NextAudio = []
    options.PulseShape {mustBeMember(options.PulseShape, {'level', 'pair'})} = 'level'
end

fs = options.SamplingRate;

if istext(audio)
    % Assume this is a path - load the audio
    [audio, fs_loaded] = audioread(audio);
    if isempty(fs)
        fs = fs_loaded;
    end
end
if istext(options.NextAudio)
    options.NextAudio = audioread(options.NextAudio);
end

% If audio is multi-channel, select one channel
if size(audio, 2) > 1
    audio = audio(:, options.Channel);
end
if size(options.NextAudio, 2) > 0
    options.NextAudio = options.NextAudio(:, options.Channel);
end

% Calculate number of audio samples in file or vector
num_samples = length(audio);

% Empirically determined delay between relay deactivation and click sound.
%   Only applies to the legacy acoustic 'pair' signal; the directly-recorded
%   'level' pulse has no such delay.
switch options.PulseShape
    case 'pair'
        pulse_delay = 0.0035;
    case 'level'
        pulse_delay = 0.0;
end
% Adjust pulse time
pulse_time = pulse_time + pulse_delay;
% Tolerance for variation in relay turn-off time
pulse_tolerance = 0.12 * pulse_time;
% Convert pulse times to samples
pulse_samples = pulse_time * fs;
pulse_tolerance_samples = pulse_tolerance * fs;
% Debounce signal such that any repeated onsets spaced closer than half the\
%   pulse time are ignored.
debounce_time = pulse_time / 2;
% Convert debounce time to audio samples
debounce_samples = debounce_time * fs;

if size(options.NextAudio, 1) > 0
    % How far do we want to look into the next file?
    next_bit = round(10 * pulse_samples);

    % Only need a bit of the next audio
    if size(options.NextAudio) > next_bit
        options.NextAudio = options.NextAudio(1:next_bit);
    end

    % Tack on the next audio
    audio = [audio; options.NextAudio];
end

onsets = [];
offsets = [];

switch options.PulseShape
    case 'level'
        % Directly-recorded sync signal (e.g. the DAQ wired straight to the
        %   LED power): each pulse is a single sustained "high" level lasting
        %   ~pulse_time. The onset is the rising edge of that level, validated
        %   by a matching falling edge ~pulse_time later. This is the same
        %   model used for the video sync flashes in findSyncFlashOnsets.
        level = abs(audio) > threshold;
        % Rising and falling threshold crossings, debounced to collapse any
        %   chatter around each edge into a single event.
        click_starts = debounceEdges(find(diff(level) > 0), debounce_samples, nan);
        click_ends = debounceEdges(find(diff(level) < 0), debounce_samples, 0);

        for k = 1:length(click_starts)
            % A pulse's falling edge must come before the next pulse's onset
            if k < length(click_starts)
                possible_ends = click_ends(click_ends < click_starts(k+1));
            else
                possible_ends = click_ends;
            end
            % Keep this onset only if a falling edge lands ~pulse_time later
            predicted_end = click_starts(k) + pulse_samples;
            matching_ends = possible_ends( ...
                floor(predicted_end - pulse_tolerance_samples) <= possible_ends & ...
                possible_ends <= ceil(predicted_end + pulse_tolerance_samples));
            if ~isempty(matching_ends)
                onsets(end+1) = click_starts(k) + 1; %#ok<*AGROW>
                offsets(end+1) = matching_ends(1);
            end
        end

    case 'pair'
        % Legacy relay setup: each sync pulse produces two brief transient
        %   clicks (relay closing, then opening) separated by ~pulse_time,
        %   recorded acoustically by a microphone. Pair consecutive clicks
        %   that are separated by the expected pulse time.
        click_ons = find(abs(audio) > threshold);
        click_starts = [];
        % Assume there was no onset right before the start of the file
        debounce_start = nan;
        while true
            % Eliminate any following onsets that are within the debounce time
            click_ons(click_ons < (debounce_start + debounce_samples)) = [];
            % Stop loop if we're out of onsets
            if isempty(click_ons)
                break;
            end
            % Record next onset
            click_starts(end+1) = click_ons(1);
            % Reset debounce time
            debounce_start = click_ons(1);
        end

        % Look for onset/offset click pairs in click_starts. They only count
        %   as a pair if they are separated within tolerance by the pulse time.
        for k = 1:length(click_starts)-1
            separation = click_starts(k+1) - click_starts(k);
            if abs(separation - pulse_samples) < pulse_tolerance_samples
                % This is a pulse on/off pair of clicks
                onsets(end+1) = click_starts(k);
                offsets(end+1) = click_starts(k+1);
            end
        end
end

if options.PlotOnsets
    figure;
    ax = axes();
    hold(ax, 'on');
    plot(ax, (1:length(audio)) / fs, audio, 'k');
    for onset = onsets
        plot(ax, onset/fs, 0, 'g*');
    end
    for offset = offsets
        plot(ax, offset/fs, 0, 'r*');
    end
    xlabel('time (s)');
    hold(ax, 'off');
end

if ~isempty(options.NextAudio)
    % Filter out any onsets after end of file
    in_range = onsets <= num_samples;
    onsets = onsets(in_range);
    offsets = offsets(in_range);
end

function kept = debounceEdges(edges, debounce_samples, initial_debounce_start)
% Collapse threshold-crossing chatter: walk the (sorted) edge sample indices,
%   keeping each edge and discarding any that follow within debounce_samples.
%   initial_debounce_start is the reference before the first edge: use NaN to
%   always keep the first edge, or 0 to discard edges in the first window.
kept = [];
debounce_start = initial_debounce_start;
while true
    edges(edges < (debounce_start + debounce_samples)) = [];
    if isempty(edges)
        break;
    end
    kept(end+1) = edges(1);
    debounce_start = edges(1);
end