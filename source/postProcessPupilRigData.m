function sync_struct = postProcessPupilRigData(root, align_root, options)
arguments
    root {mustBeTextScalar}
    align_root {mustBeTextScalar}
    options.PulsesPerFile = 2
end

sync_struct = getPupillometryDataAlignment(root);
alignVideosToAudio(sync_struct, align_root, 'PulsesPerFile', options.PulsesPerFile);