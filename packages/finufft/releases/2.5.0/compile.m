% compile.m
% Compile FINUFFT MEX file for MIP package distribution.
%
% This script is run by mip.bundle() during package bundling.
% The working directory is the package root (full finufft repo clone).
% The MEX file is placed into matlab/ which is on the addpath.

fprintf('=== Compiling FINUFFT MEX file ===\n');

scriptDir = fileparts(mfilename('fullpath'));
finufftSrc = scriptDir;  % full repo is the package root
finufftMatlab = fullfile(scriptDir, 'matlab');
buildDir = fullfile(scriptDir, 'build_mex');

if ~exist(buildDir, 'dir')
    mkdir(buildDir);
end

% On Linux, strip MATLAB's LD_LIBRARY_PATH to avoid conflicts with host tools
envPrefix = '';
if isunix && ~ismac
    envPrefix = makeExternalEnvPrefix(matlabroot, getenv('LD_LIBRARY_PATH'));
end

% Build generator args (Ninja, etc.)
generatorArgs = '';
cmakeGenerator = strtrim(getenv('MIP_CMAKE_GENERATOR'));
cmakeBuildProgram = strtrim(getenv('MIP_CMAKE_BUILD_PROGRAM'));
if ~isempty(cmakeGenerator)
    generatorArgs = sprintf(' -G "%s"', cmakeGenerator);
end
if ~isempty(cmakeBuildProgram)
    generatorArgs = sprintf('%s -DCMAKE_MAKE_PROGRAM="%s"', generatorArgs, cmakeBuildProgram);
end

% Configure and build MEX via finufft's own CMake target
fprintf('Configuring FINUFFT with CMake...\n');
cmakeCmd = sprintf([ ...
    '%s cmake "%s" -B "%s"' ...
    '%s' ...
    ' -DCMAKE_BUILD_TYPE=Release' ...
    ' -DFINUFFT_BUILD_MATLAB=ON' ...
    ' -DMatlab_ROOT_DIR="%s"' ...
    ' -DFINUFFT_USE_OPENMP=OFF' ...
    ' -DFINUFFT_USE_DUCC0=ON' ...
    ' -DFINUFFT_STATIC_LINKING=ON' ...
    ' -DFINUFFT_BUILD_TESTS=OFF' ...
    ' -DFINUFFT_BUILD_EXAMPLES=OFF' ...
    ' -DFINUFFT_ENABLE_INSTALL=OFF' ...
    ' -DFINUFFT_ARCH_FLAGS=""'], ...
    envPrefix, finufftSrc, buildDir, generatorArgs, matlabroot);
runExternalCommand(cmakeCmd, 'CMake configuration');

fprintf('Building FINUFFT MEX target...\n');
nproc = maxNumCompThreads;
buildCmd = sprintf('%s cmake --build "%s" --config Release --target finufft_mex -j%d', ...
    envPrefix, buildDir, nproc);
runExternalCommand(buildCmd, 'CMake build');

% Copy MEX file into matlab/ (which is on the addpath)
mexName = ['finufft.' mexext];
results = dir(fullfile(buildDir, '**', mexName));
if isempty(results)
    error('MEX file %s not found in build directory %s', mexName, buildDir);
end
mexDest = fullfile(finufftMatlab, mexName);
copyfile(fullfile(results(1).folder, results(1).name), mexDest);
fprintf('MEX file created: %s\n', mexDest);

% Strip unnecessary shared library dependencies added by matlab_add_mex().
if isunix
    [~, ~] = system(sprintf('%s patchelf --remove-needed libMatlabEngine.so "%s" 2>/dev/null', envPrefix, mexDest));
end

% Clean up build artifacts that should not be bundled
fprintf('Cleaning up build artifacts...\n');
if exist(buildDir, 'dir')
    rmdir(buildDir, 's');
end

% Remove source directories that are not needed at runtime
for d = {"src", "include", "contrib", "CMakeLists.txt", "cmake", "make.inc*", "dcalculating"}
    p = fullfile(scriptDir, d{1});
    if exist(p, 'dir')
        rmdir(p, 's');
    elseif exist(p, 'file')
        delete(p);
    end
end

fprintf('=== FINUFFT MEX compilation complete ===\n');

function envPrefix = makeExternalEnvPrefix(matlabRoot, currentLdLibraryPath)
cleanPath = stripMatlabPaths(currentLdLibraryPath, matlabRoot);
if isempty(cleanPath)
    envPrefix = 'env -u LD_PRELOAD -u LD_LIBRARY_PATH';
else
    envPrefix = sprintf('env -u LD_PRELOAD LD_LIBRARY_PATH=''%s''', cleanPath);
end
end

function cleanPath = stripMatlabPaths(ldLibraryPath, matlabRoot)
if isempty(ldLibraryPath)
    cleanPath = '';
    return;
end
pathEntries = strsplit(ldLibraryPath, pathsep);
keepEntries = {};
normalizedRoot = strrep(matlabRoot, '\', '/');
for i = 1:numel(pathEntries)
    entry = strtrim(pathEntries{i});
    if isempty(entry), continue; end
    if contains(strrep(entry, '\', '/'), normalizedRoot), continue; end
    keepEntries{end + 1} = entry; %#ok<AGROW>
end
cleanPath = strjoin(keepEntries, pathsep);
end

function runExternalCommand(command, stepName)
[status, output] = system(command);
fprintf('%s', output);
if status ~= 0
    error('%s failed (exit code %d)', stepName, status);
end
end
