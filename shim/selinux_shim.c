// LD_PRELOAD for OriginOS init inside a container: the host kernel has no SELinux,
// so answer libselinux queries the way a permissive device would instead of failing.
// Built against bionic with no headers on purpose (see scripts/build_shim.sh).
typedef unsigned short security_class_t;
extern char *strdup(const char *);

static int ctx(char **out, const char *c) { *out = strdup(c); return 0; }

int getcon(char **con) { return ctx(con, "u:r:init:s0"); }
int getpeercon(int fd, char **con) { (void)fd; return ctx(con, "u:r:init:s0"); }
int security_compute_create(const char *s, const char *t, security_class_t c, char **out) {
  // must differ from getcon(), or init refuses the exec as "no domain transition"
  (void)s; (void)t; (void)c; return ctx(out, "u:r:container_svc:s0");
}
int getfilecon(const char *p, char **con) { (void)p; ctx(con, "u:object_r:system_file:s0"); return 26; }
int lgetfilecon(const char *p, char **con) { (void)p; ctx(con, "u:object_r:system_file:s0"); return 26; }

int lsetfilecon(const char *p, const char *c) { (void)p; (void)c; return 0; }
int setexeccon(const char *c) { (void)c; return 0; }
int setfscreatecon(const char *c) { (void)c; return 0; }
int setsockcreatecon(const char *c) { (void)c; return 0; }
security_class_t string_to_security_class(const char *n) { (void)n; return 1; }
int selinux_check_access(const char *s, const char *t, const char *c, const char *p, void *a) {
  (void)s; (void)t; (void)c; (void)p; (void)a; return 0;
}
int selinux_android_restorecon(const char *p, unsigned int f) { (void)p; (void)f; return 0; }
int security_getenforce(void) { return 0; }
int security_setenforce(int v) { (void)v; return 0; }
int security_load_policy(void *d, unsigned long n) { (void)d; (void)n; return 0; }

// Everything below is for the rest of the system (servicemanager, logd, zygote...),
// which gets this library through `export LD_PRELOAD` in container.rc.
int getpidcon(int pid, char **con) { (void)pid; return ctx(con, "u:r:init:s0"); }
int getprevcon(char **con) { return ctx(con, "u:r:init:s0"); }
int setcon(const char *c) { (void)c; return 0; }
int selinux_android_setcon(const char *c) { (void)c; return 0; }
int selinux_android_setcontext(unsigned uid, int sys, const char *seinfo, const char *name) {
  (void)uid; (void)sys; (void)seinfo; (void)name; return 0;
}
int selinux_status_open(int fallback) { (void)fallback; return 0; }
int selinux_status_updated(void) { return 0; }
int selinux_status_getenforce(void) { return 0; }
void selinux_status_close(void) {}

// Context lookups: hand out a dummy handle and a generic label.
static char dummy_handle[64];
void *selinux_android_service_context_handle(void) { return dummy_handle; }
void *selinux_android_hw_service_context_handle(void) { return dummy_handle; }
void *selinux_android_vendor_service_context_handle(void) { return dummy_handle; }
void *selinux_android_keystore2_key_context_handle(void) { return dummy_handle; }
void selabel_close(void *h) { (void)h; }
int selabel_lookup(void *h, char **con, const char *key, int type) {
  (void)h; (void)key; (void)type; return ctx(con, "u:object_r:default_android_service:s0");
}
// servicemanager asks binder for caller security contexts (SET_CONTEXT_MGR_EXT with
// TXN_SECURITY_CTX). Without an LSM that provides them the kernel then fails every call
// to it, so refuse EXT: libbinder falls back to plain SET_CONTEXT_MGR and getpidcon().
#define BINDER_SET_CONTEXT_MGR_EXT 0x4018620du  // _IOW('b', 13, struct flat_binder_object)
#define RTLD_NEXT ((void *)-1L)
extern void *dlsym(void *, const char *);
extern int *__errno(void);
int ioctl(int fd, int req, ...) {
  static int (*real)(int, int, ...);
  __builtin_va_list ap;
  __builtin_va_start(ap, req);
  void *arg = __builtin_va_arg(ap, void *);
  __builtin_va_end(ap);
  if ((unsigned)req == BINDER_SET_CONTEXT_MGR_EXT) { *__errno() = 22; return -1; }
  if (!real) real = (int (*)(int, int, ...))dlsym(RTLD_NEXT, "ioctl");
  return real(fd, req, arg);
}

// ...and servicemanager insists on a caller SID for every incoming call
// (CHECK "Did not get context from PID"), so hand one out.
const char *_ZNK7android14IPCThreadState13getCallingSidEv(const void *self) {
  (void)self; return "u:r:init:s0";
}
// Services that mark their own binders "requesting SID" (keystore2, keymint...) make the
// kernel fail every call to them for the same reason; getCallingSid() above covers them.
void _ZN7android7BBinder16setRequestingSidEb(void *self, _Bool b) { (void)self; (void)b; }
void _ZN7android8hardware9BHwBinder16setRequestingSidEb(void *self, _Bool b) { (void)self; (void)b; }
void _ZN7android8hardware16setRequestingSidERKNS_2spINS_4hidl4base4V1_05IBaseEEEb(const void *s, _Bool b) {
  (void)s; (void)b;
}
// same for hwservicemanager (libhwbinder)
const char *_ZNK7android8hardware14IPCThreadState13getCallingSidEv(const void *self) {
  (void)self; return "u:r:init:s0";
}

// Per-service cgroups: after post-fs-data init cannot create them in the container
// ("Read-only file system") and treats that as fatal. Services just share the
// container's cgroup instead.
int _Z18createProcessGroupjib(unsigned uid, int pid, _Bool mem) { (void)uid; (void)pid; (void)mem; return 0; }
int _Z24createProcessGroupByNamePKcji(const char *n, unsigned uid, int pid) { (void)n; (void)uid; (void)pid; return 0; }
_Bool _Z20setProcessGroupLimitjil(unsigned uid, int pid, long v) { (void)uid; (void)pid; (void)v; return 1; }
_Bool _Z24setProcessGroupSoftLimitjil(unsigned uid, int pid, long v) { (void)uid; (void)pid; (void)v; return 1; }
_Bool _Z25setProcessGroupSwappinessjii(unsigned uid, int pid, int v) { (void)uid; (void)pid; (void)v; return 1; }

int selabel_lookup_best_match(void *h, char **con, const char *key, const char **aliases, int type) {
  (void)h; (void)key; (void)aliases; (void)type; return ctx(con, "u:object_r:system_file:s0");
}
