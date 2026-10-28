# Keep synthesis workers bounded after a native parallel synthesis crash.
set_param general.maxThreads 1
set_param synth.maxThreads 1
