#import "ExtractorBridge.h"
#import <Python/Python.h>

@implementation VSExtractorBridge

static int runtimeState = 0;

+ (BOOL)initializeRuntime {
    if (runtimeState != 0) return runtimeState == 1;
    runtimeState = -1;
    NSString *resources = NSBundle.mainBundle.resourcePath;
    NSString *home = [resources stringByAppendingPathComponent:@"python"];
    if (![NSFileManager.defaultManager fileExistsAtPath:home]) return NO;
    PyPreConfig preconfig;
    PyPreConfig_InitIsolatedConfig(&preconfig);
    preconfig.utf8_mode = 1;
    PyStatus status = Py_PreInitialize(&preconfig);
    if (PyStatus_Exception(status)) return NO;
    PyConfig config;
    PyConfig_InitIsolatedConfig(&config);
    config.write_bytecode = 0;
    config.install_signal_handlers = 0;
    config.use_system_logger = 0;
    status = PyConfig_SetBytesString(&config, &config.home, home.UTF8String);
    if (!PyStatus_Exception(status)) status = Py_InitializeFromConfig(&config);
    PyConfig_Clear(&config);
    if (PyStatus_Exception(status)) return NO;
    BOOL ready = YES;
    for (NSString *folder in @[@"ExtractorPackages", @"ExtractorPython"]) {
        NSString *path = [resources stringByAppendingPathComponent:folder];
        PyObject *value = PyUnicode_FromString(path.UTF8String);
        if (value == NULL || PyList_Insert(PySys_GetObject("path"), 0, value) != 0) ready = NO;
        Py_XDECREF(value);
    }
    if (!ready) PyErr_Clear();
    runtimeState = ready ? 1 : -1;
    // Future queue blocks may run on different OS threads; acquire the GIL per job.
    PyEval_SaveThread();
    return ready;
}

+ (nullable NSString *)resolveAddress:(NSString *)address error:(NSError **)error {
        if (![self initializeRuntime]) {
            if (error) *error = [NSError errorWithDomain:@"VisionStreamExtractor" code:1 userInfo:nil];
            return nil;
        }
        PyGILState_STATE gil = PyGILState_Ensure();
        PyObject *module = PyImport_ImportModule("visionstream_resolver");
        PyObject *function = module ? PyObject_GetAttrString(module, "resolve") : NULL;
        PyObject *argument = PyUnicode_FromString(address.UTF8String);
        PyObject *result = function && argument && PyCallable_Check(function)
            ? PyObject_CallOneArg(function, argument) : NULL;
        const char *utf8 = result && PyUnicode_Check(result) ? PyUnicode_AsUTF8(result) : NULL;
        NSString *output = utf8 ? [NSString stringWithUTF8String:utf8] : nil;
        Py_XDECREF(result); Py_XDECREF(argument); Py_XDECREF(function); Py_XDECREF(module);
        // Never print a Python exception: it can contain account data or signed URLs.
        if (PyErr_Occurred()) PyErr_Clear();
        PyGILState_Release(gil);
        if (!output && error) *error = [NSError errorWithDomain:@"VisionStreamExtractor" code:2 userInfo:nil];
        return output;
}
@end
