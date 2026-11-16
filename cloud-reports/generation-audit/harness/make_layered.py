import importlib.util, sys
spec = importlib.util.spec_from_file_location("layered", "/home/user/bench/Scripts/benchmark-2-3-1/layered.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
k = int(sys.argv[2])
m.LAYER_SIZES = [s * k for s in [20, 20, 20, 20, 15, 5]]
m.write_shape(sys.argv[1], seams=sys.argv[3] == "seams")
