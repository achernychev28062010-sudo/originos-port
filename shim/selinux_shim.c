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
int selabel_lookup_best_match(void *h, char **con, const char *key, const char **aliases, int type) {
  (void)h; (void)key; (void)aliases; (void)type; return ctx(con, "u:object_r:system_file:s0");
}
