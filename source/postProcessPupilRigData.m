function sync_struct = postProcessPupilRigData(data_root, align_root, options)
arguments
    data_root {mustBeTextScalar}
    align_root {mustBeTextScalar}
    options.PulsesPerFile = 2
    options.SyncStruct = struct.empty()
    options.NaneyeNumIgnoredPulses = 0
    options.WebcamNumIgnoredPulses = 0
    options.AudioNumIgnoredPulses = 0
    options.FileLimit = []
    options.ClickChannel = 1
    options.NaneyeBadSyncFileIdx = []
    options.WebcamBadSyncFileIdx = []
    options.AudioBadSyncFileIdx = []
    options.WebcamROI = [1, 1, 50, 50]
    options.NaneyeROI = [200, 1, 50, 50]
    options.IncludeNaneye = true
    options.IncludeWebcam = true
end

sync_struct = struct.empty();

if isempty(options.SyncStruct) 
    if istext(options.SyncStruct)
        % Empty string means use the default saved .mat file
        try
            % Get default path for alignment struct .mat file
            default_path = getAlignmentStructPath(data_root);
            % Load data
            S = load(default_path);
            % Attempt to get sync_struct
            sync_struct = S.sync_struct;
        catch ME
            if strcmp(ME.identifier, 'MATLAB:load:couldNotReadFile')
                fprintf('No sync struct found in file %s\n\nGenerating sync_struct...\n', default_path);
            else
                fprintf('Something went wrong loading default sync struct...generating new one...\n')
                disp(ME.message)
            end
            sync_struct = struct.empty();
        end
    end
elseif istext(options.SyncStruct)
    % User passed a non-empty string - try to use it as a path to load from
    try
        % Load data
        S = load(options.SyncStruct);
        % Attempt to get sync_struct
        sync_struct = S.sync_struct;
    catch ME
        if strcmp(ME.identifier, 'MATLAB:load:couldNotReadFile')
            fprintf('No sync struct found in file %s\n\nGenerating sync_struct...\n', options.SyncStruct);
            sync_struct = struct.empty();
        else
            rethrow(ME);
        end
    end
end

if isempty(sync_struct)
    % options.SyncStruct is still empty - generate it from scratch
    sync_struct = getPupillometryDataAlignment( ...
        data_root, ...
        'NaneyeNumIgnoredPulses', options.NaneyeNumIgnoredPulses, ...
        'WebcamNumIgnoredPulses', options.WebcamNumIgnoredPulses, ...
        'AudioNumIgnoredPulses', options.AudioNumIgnoredPulses, ...
        'NaneyeBadSyncFileIdx', options.NaneyeBadSyncFileIdx, ...
        'WebcamBadSyncfileIdx', options.WebcamBadSyncFileIdx, ...
        'AudioBadSyncfileIdx', options.AudioBadSyncFileIdx, ...
        'FileLimit', options.FileLimit, ...
        'ClickChannel', options.ClickChannel, ...
        'WebcamROI', options.WebcamROI, ...
        'NaneyeROI', options.NaneyeROI, ...
        'IncludeNaneye', options.IncludeNaneye, ...
        'IncludeNaneye', options.IncludeWebcam ...
        );
end

alignVideosToAudio(sync_struct, align_root, ...
    'PulsesPerFile', options.PulsesPerFile, ...
    'VideoClicks', false, ...
    'ClickChannel', options.ClickChannel, ...
    'IncludeNaneye', options.IncludeNaneye, ...
    'IncludeNaneye', options.IncludeWebcam ...
    );