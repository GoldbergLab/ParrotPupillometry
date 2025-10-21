function click_struct = makeAudioSyncStruct(root_directory, threshold, pulse_time, options)
arguments
    root_directory
    threshold double = 0.01
    pulse_time double = 0.08
    options.Channel double = 1
    options.NumIgnoredClicks = 0
end

audio_files = findFiles(root_directory, '.*\.wav', 'SearchSubdirectories', false);
num_files = length(audio_files);

% Initialize structure
click_struct(num_files) = struct();

cumulative_samples = 0;

for k = 1:num_files
    audio_file = audio_files{k};
    click_struct(k).path = audio_file;
    [onsets, offsets, num_samples, fs] = findSyncClickOnsets(audio_file, threshold, pulse_time, 'Channel', options.Channel);

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
