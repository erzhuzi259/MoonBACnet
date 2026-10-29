/* Original argv-only Windows compatibility adapter for Moon 20261016.
 * OCaml tools reject the driver's \\?\ output paths. Normalize the prefix
 * at the process boundary; never invoke a shell or modify compiler outputs. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <wchar.h>
#include <stdlib.h>
#include <stdio.h>

static void quoted(wchar_t **out, const wchar_t *arg) {
    *(*out)++ = L'"';
    while (*arg) {
        size_t slashes = 0;
        while (*arg == L'\\') { ++slashes; ++arg; }
        size_t count = (*arg == L'"' || !*arg) ? slashes * 2 : slashes;
        for (size_t i = 0; i < count; ++i) *(*out)++ = L'\\';
        if (*arg == L'"') *(*out)++ = L'\\';
        if (*arg) *(*out)++ = *arg++;
    }
    *(*out)++ = L'"';
}

int wmain(int argc, wchar_t **argv) {
    wchar_t module[32768], tool[32768];
    if (!GetModuleFileNameW(NULL, module, 32768)) return 125;
    wchar_t *name = wcsrchr(module, L'\\');
    const wchar_t *root = _wgetenv(L"MOON_TOOLCHAIN_ROOT");
    const wchar_t *profile = _wgetenv(L"USERPROFILE");
    if (!name || (!root && !profile)) return 125;
    if (root) swprintf_s(tool, 32768, L"%ls\\bin\\%ls", root, name + 1);
    else swprintf_s(tool, 32768, L"%ls\\.moon\\bin\\%ls", profile, name + 1);
    if (_wcsicmp(module, tool) == 0) return 125;
    size_t capacity = 2 * wcslen(tool) + 4;
    for (int i = 1; i < argc; ++i) capacity += 2 * wcslen(argv[i]) + 4;
    if (capacity > 32767) return 125;
    wchar_t *command = calloc(capacity, sizeof(wchar_t)), *at = command;
    if (!command) return 125;
    quoted(&at, tool);
    for (int i = 1; i < argc; ++i) {
        const wchar_t *arg = argv[i];
        /* Keep UNC paths as UNC: only DOS drive paths are normalized. */
        if (wcsncmp(arg, L"\\\\?\\", 4) == 0 && wcslen(arg) >= 7 && arg[5] == L':') arg += 4;
        *at++ = L' '; quoted(&at, arg);
    }
    *at = 0;
    STARTUPINFOW si = { sizeof(si) };
    PROCESS_INFORMATION pi = {0};
    BOOL started = CreateProcessW(tool, command, NULL, NULL, TRUE, 0, NULL, NULL, &si, &pi);
    free(command);
    if (!started) { fwprintf(stderr, L"Moon path adapter launch error %lu\n", GetLastError()); return 125; }
    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD code = 125;
    GetExitCodeProcess(pi.hProcess, &code);
    CloseHandle(pi.hThread); CloseHandle(pi.hProcess);
    return (int)code;
}
