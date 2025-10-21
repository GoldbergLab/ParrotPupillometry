function [collected_data, index_info, collected_filled] = collect_sync_pulse_period_data(this_path, next_path, this_drop_info, next_drop_info, this_onset, next_onset, cache, loader, data_slicer, data_sizer, data_combiner, data_drop_fixer, options)
arguments
    this_path char
    next_path char
    this_drop_info
    next_drop_info
    this_onset double
    next_onset double
    cache
    loader = []
    data_slicer = []
    data_sizer = []
    data_combiner = []
    data_drop_fixer = []
    options.MaxCacheSize = 9
    options.Debug = false
    options.DataType {mustBeMember(options.DataType, {'audio', 'video', 'none'})} = 'audio'
end
if options.Debug
    disp('LOADING PULSE PERIOD DATA')
end

% Define utility functions
switch options.DataType
    case 'none'
        % User is going to specify all data handler functions explicitly
    case 'audio'
        if isempty(loader)
            loader = @audioread;
        end
        if isempty(data_slicer)
            data_slicer = @(data, start, stop)data(start:stop, :);
        end
        if isempty(data_sizer)
            data_sizer = @(data)size(data, 1);
        end
        if isempty(data_combiner)
            data_combiner = @(data1, data2)[data1; data2];
        end
        if isempty(data_drop_fixer)
        end
    case 'video'
        if isempty(loader)
            loader = @(path)fastVideoReader(path);
        end
        if isempty(data_slicer)
            data_slicer = @(data, start, stop)data(:, :, :, start:stop);
        end
        if isempty(data_sizer)
            data_sizer = @(data)size(data, 4);
        end
        if isempty(data_combiner)
            data_combiner = @(data1, data2)cat(4, data1, data2);
        end
        if isempty(data_drop_fixer)
            data_drop_fixer = @fillInDroppedVideoFrames;
        end
end

% Load initial file
data = cacheLoadFile(this_path, loader, cache, 'MaxLength', options.MaxCacheSize);

% If data has drops, fix the drops here, and save info about where the drops are
if ~isempty(this_drop_info)
    [data, filled] = data_drop_fixer(data, this_drop_info);
else
    filled = false([1, data_sizer(data)]);
end

% Pulse period starts at pulse onset, of course
start_sample = this_onset;

pulse_spans_two_files = ~strcmp(this_path, next_path);

if ~pulse_spans_two_files
    % Whole pulse period is contained within this file
    end_sample = next_onset-1;
else
    % Pulse period spans two files
    end_sample = data_sizer(data);
end

% Slice data from pulse start to whichever end sample is appropriate
collected_data = data_slicer(data, start_sample, end_sample);
% Collect info about how data was sliced for posterity
index_info = struct();
index_info.path = this_path;
index_info.start_sample = start_sample;
index_info.end_sample = end_sample;
if options.Debug
    [~, name, ext] = fileparts(this_path);
    fprintf('Loading %06d - %06d from %s\n', start_sample, end_sample, [name, ext]);
end

% If data has drops and save info about where the drops are
collected_filled = filled(start_sample:end_sample);

if  pulse_spans_two_files
    % Pulse period spans two files - load second file chunk
    data2 = cacheLoadFile(next_path, loader, cache, 'MaxLength', options.MaxCacheSize);
    if ~isempty(next_drop_info)
        [data2, filled2] = data_drop_fixer(data2, next_drop_info);
    else
        filled2 = false([1, data_sizer(data2)]);
    end

    % Start chunk at the beginning of file 2
    start_sample = 1;
    % And just before next pulse onset
    end_sample = next_onset-1;
    % Slice data from start of file 2 to just before next onset
    next_collected_data = data_slicer(data2, start_sample, end_sample);
    % Combine the previous slice with this one
    collected_data = data_combiner(collected_data, next_collected_data);
    % Combine filled info too
    collected_filled = [collected_filled, filled2(start_sample, end_sample)];
    % Collect info about how data was sliced for posterity
    index_info(2).path = next_path;
    index_info(2).start_sample = start_sample;
    index_info(2).end_sample = end_sample;
    if options.Debug
        [~, name, ext] = fileparts(this_path);
        fprintf('Loading %06d - %06d from %s\n', start_sample, end_sample, [name, ext]);
    end
end