package pegasus

CapKind :: enum {
  Cclose,  /* not used in trees */
  Cposition,
  Cconst,  /* ktable[key] is Lua constant */
  Cbackref,  /* ktable[key] is "name" of group to get capture */
  Carg,  /* 'key' is arg's number */
  Csimple,  /* next node is pattern */
  Ctable,  /* next node is pattern */
  Cfunction,  /* ktable[key] is function; next node is pattern */
  Cquery,  /* ktable[key] is table; next node is pattern */
  Cstring,  /* ktable[key] is string; next node is pattern */
  Cnum,  /* numbered capture; 'key' is number of value to return */
  Csubst,  /* substitution capture; next node is pattern */
  Cfold,  /* ktable[key] is function; next node is pattern */
  Cruntime,  /* not used in trees (is uses another type for tree) */
  Cgroup  /* ktable[key] is group's "name" */
}

Capture :: struct {
	s:    string, /* subject position */
	idx:  u16, /* extra info (group name, arg index, etc.) */
	kind: CapKind, /* kind of capture */
	siz:  byte, /* size of full capture + 1 (0 = not a full capture) */
}

