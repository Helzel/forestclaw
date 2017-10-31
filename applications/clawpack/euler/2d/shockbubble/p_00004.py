# comment = "Torus example : eff. resolution = 2048 x 2048"
import sys
import os
import subprocess
import random

arg_list = ["mpirun","-n","4","shockbubble"]
jobid = random.randint(1000,9999)
outfile = "shockbubble_00004.o%d" % (jobid)
f = open(outfile,'w')
po = subprocess.Popen(arg_list,stdout=f)
print "Starting process %d with jobid %d on 4 processor(s)." % (po.pid,jobid)
po.wait()
