function click_struct = makeAudioSyncStruct(root_directory, threshold, pulse_time, options)
arguments
    root_directory
    threshold double = 0.01
    pulse_time double = 0.08
    options.Channel double = 1
    options.NumIgnoredClicks = 0
    options.FileLimit = []
    options.BadSyncFileIdx = []
    options.PlotOnsets = false
end

audio_files = findPaths(root_directory, '.*\.wav', 'SearchSubdirectories', false);
if ~isempty(options.FileLimit) && length(audio_files) > options.FileLimit
    % User requests limited number of audio files
    audio_files = audio_files(1:options.FileLimit);
end
num_files = length(audio_files);

% Initialize structure
click_struct(num_files) = struct();

cumulative_samples = 0;

for k = 1:num_files
    audio_file = audio_files{k};
    click_struct(k).path = audio_file;
    data = cacheLoadFile(audio_file, @audioloader);
    audio_data = data{1};
    fs = data{2};

    if k < num_files
        next_data = cacheLoadFile(audio_files{k+1}, @audioloader);
        next_audio_data = next_data{1};
    else
        next_audio_data = zeros(0, size(audio_data, 2));
    end

    if ~ismember(k, options.BadSyncFileIdx)
        % User indicates this video should have good sync signal
        [onsets, offsets, num_samples, fs] = findSyncClickOnsets( ...
            audio_data, ...
            threshold, ...
            pulse_time, ...
            'NextAudio', next_audio_data, ...
            'SamplingRate', fs, ...
            'Channel', options.Channel, ...
            'PlotOnsets', options.PlotOnsets ...
            );
    else
        % Users indicates sync signal is bad in this file
        %   Leave onsets/offsets empty, just determine number of samples 
        %   and sample rate.
        onsets = [];
        offsets = [];
        num_samples = size(audio_data, 1);
    end

    if options.NumIgnoredClicks > 0
        if length(onsets) <= options.NumIgnoredClicks
            options.NumIgnoredClicks = options.NumIgnoredClicks - length(onsets);
            onsets = [];
            offsets = [];
        else
            onsets(1:options.NumIgnoredClicks) = [];
            offsets(1:options.NumIgnoredClicks) = [];
            options.NumIgnoredClicks = 0;
        end
    end
    
    click_struct(k).onsets = onsets;
    click_struct(k).offsets = offsets;
    click_struct(k).onsets_cumulative = onsets + cumulative_samples;
    click_struct(k).offsets_cumulative = offsets + cumulative_samples;
    click_struct(k).num_samples = num_samples;
    click_struct(k).fs = fs;
    cumulative_samples = cumulative_samples + num_samples;
end

function data = audioloader(path)
[y, fs] = audioread(path);
data = {y, fs};