% Bundle all prepared packages using mip bundle.
%
% This script discovers all prepared directories in build/prepared/
% and calls mip.bundle() on each to produce .mhl files in build/bundled/.
%
% Expected to be run from the repository root directory.

fprintf('=== Bundle Packages ===\n');

preparedDir = fullfile(pwd, 'build', 'prepared');
outputDir = fullfile(pwd, 'build', 'bundled');

architecture = getenv('BUILD_ARCHITECTURE');
if isempty(architecture)
    % err
    error('mip:missingArchitecture', 'Environment variable BUILD_ARCHITECTURE is not set');
end

if ~exist(preparedDir, 'dir')
    fprintf('No prepared directory found at %s. Nothing to bundle.\n', preparedDir);
    return;
end

if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end

% List prepared directories
items = dir(preparedDir);
bundled = 0;
failed = 0;

for i = 1:length(items)
    if ~items(i).isdir || startsWith(items(i).name, '.')
        continue;
    end

    pkgDir = fullfile(preparedDir, items(i).name);

    % Check for mip.yaml
    if ~exist(fullfile(pkgDir, 'mip.yaml'), 'file')
        fprintf('Skipping %s (no mip.yaml)\n', items(i).name);
        continue;
    end

    fprintf('\n--- Bundling: %s ---\n', items(i).name);

    try
        % Apply compiler environment from .compiler_env (SIMD builds)
        originalEnv = struct();
        compilerEnvFile = fullfile(pkgDir, '.compiler_env');
        if exist(compilerEnvFile, 'file')
            fid = fopen(compilerEnvFile, 'r');
            envData = jsondecode(fread(fid, '*char')');
            fclose(fid);
            envNames = fieldnames(envData);
            for j = 1:length(envNames)
                originalEnv.(envNames{j}) = getenv(envNames{j});
                setenv(envNames{j}, char(string(envData.(envNames{j}))));
                fprintf('  Setting %s=%s\n', envNames{j}, char(string(envData.(envNames{j}))));
            end
        end

        % Build bundle args (with optional --cpu-level)
        bundleArgs = {pkgDir, '--output', outputDir, '--arch', architecture};
        cpuLevelFile = fullfile(pkgDir, '.cpu_level');
        if exist(cpuLevelFile, 'file')
            cpuLevel = strtrim(fileread(cpuLevelFile));
            bundleArgs = [bundleArgs, {'--cpu-level', cpuLevel}];
            fprintf('  CPU level: %s\n', cpuLevel);
        end

        mip.bundle(bundleArgs{:});
        bundled = bundled + 1;

        % Restore compiler environment
        if exist(compilerEnvFile, 'file')
            envNames = fieldnames(originalEnv);
            for j = 1:length(envNames)
                setenv(envNames{j}, originalEnv.(envNames{j}));
            end
        end
    catch ME
        % Restore compiler environment on failure too
        if exist('originalEnv', 'var') && isstruct(originalEnv)
            envNames = fieldnames(originalEnv);
            for j = 1:length(envNames)
                setenv(envNames{j}, originalEnv.(envNames{j}));
            end
        end
        fprintf('Error bundling %s: %s\n', items(i).name, ME.message);
        failed = failed + 1;
    end
end

fprintf('\n=== Bundle Summary ===\n');
fprintf('Bundled: %d\n', bundled);
fprintf('Failed: %d\n', failed);

if failed > 0
    error('mip:bundleFailed', '%d package(s) failed to bundle', failed);
end
