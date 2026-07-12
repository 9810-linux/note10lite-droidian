// SPDX-License-Identifier: GPL-2.0
/*
 * Droidian/Halium D0 bring-up /init for the r7 (Samsung Galaxy Note 10 Lite,
 * SM-N770F, Exynos 9810) downstream 4.9 kernel — SCREEN-FIRST observation.
 *
 * NOT the full Droidian initramfs-tools initramfs. This is a minimal D0 probe
 * (milestone D0 = "kernel downstream boot + Halium initramfs jalan, log
 * terlihat") that proves the downstream 4.9 kernel — Halium config deltas +
 * entire Knox stack disabled (TASK 2, sesi 8) — boots via the stock S-Boot path
 * and reaches userspace /init.
 *
 * SCREEN-FIRST (no UART jig required): the downstream kernel has every driver
 * (CMU, DECON/fbcon, UFS, UART), so fbcon comes up early and reliably — unlike
 * the mainline track where the missing CMU driver left early output invisible.
 * Here the physical screen (tty0) is the primary observation channel. The
 * banner is written EXPLICITLY to /dev/tty0 (and /dev/ttySAC0 if present) so it
 * appears on screen regardless of which `console=` is last on the cmdline
 * (Linux binds /dev/console = init's stdout to the LAST console= argument, so
 * relying on stdout alone would send the banner to UART-only if ttySAC0 is
 * last — invisible to a user with no jig). We also dump /proc/version,
 * /proc/cmdline and /proc/meminfo to the screen so, with no UART, you can still
 * confirm WHICH kernel ran and that the Halium cmdline took.
 *
 * Why freestanding (no libc): the host's aarch64 cross-gcc has no glibc sysroot
 * (sys/mount.h etc. are missing). Raw aarch64 syscalls avoid that dependency:
 *   aarch64-linux-gnu-gcc -nostdlib -ffreestanding -static -O2 -s -o init init.c
 *
 * Scope: mount virtual fs, print a D0 banner + key /proc info to screen (+UART),
 * loop forever (so /init never exits → no kernel panic). Mounting the userdata
 * rootfs and switch_root into Droidian systemd is the full Halium initramfs
 * (D1, Docker-packaging follow-up). See PROGRESS.md TASK 2.5 note +
 * docs/safety-unbrick.md for the flash-test-observe-restore protocol.
 */

typedef unsigned long size_t;
typedef long ssize_t;

/* aarch64 (asm-generic) syscall numbers */
#define SYS_openat  56
#define SYS_close   57
#define SYS_read    63
#define SYS_write   64
#define SYS_mount  165
#define SYS_nanosleep 101

#define AT_FDCWD  (-100)
#define O_RDONLY  0
#define O_WRONLY  1

static long sc(long n, long a, long b, long c, long d, long e, long f)
{
	register long r8 __asm__("x8") = n;
	register long r0 __asm__("x0") = a;
	register long r1 __asm__("x1") = b;
	register long r2 __asm__("x2") = c;
	register long r3 __asm__("x3") = d;
	register long r4 __asm__("x4") = e;
	register long r5 __asm__("x5") = f;
	__asm__ volatile("svc 0"
		: "+r"(r0)
		: "r"(r8), "r"(r1), "r"(r2), "r"(r3), "r"(r4), "r"(r5)
		: "memory", "cc");
	return r0;
}

void *memcpy(void *d, const void *s, size_t n) { char *dd = d; const char *ss = s; while (n--) *dd++ = *ss++; return d; }
void *memset(void *d, int c, size_t n) { char *dd = d; while (n--) *dd++ = (char)c; return d; }

static int str_eq(const char *a, const char *b) { while (*a && *a==*b) {a++;b++;} return *a==*b; }

/* output channels: stdout (/dev/console) + /dev/tty0 (screen) + /dev/ttySAC0 (UART) */
#define NOUT 3
static int out[NOUT];   /* valid fds, or -1 */

static void emit(const char *s)
{
	const char *p = s; while (*p) p++;
	size_t n = (size_t)(p - s);
	for (int i = 0; i < NOUT; i++)
		if (out[i] >= 0) sc(SYS_write, out[i], (long)s, (long)n, 0, 0, 0);
}

static int open_(const char *path, int flags)
{
	return (int)sc(SYS_openat, AT_FDCWD, (long)path, flags, 0, 0, 0);
}

static char buf[4096];
static void cat(const char *path, const char *label)
{
	emit(label);
	int fd = open_(path, O_RDONLY);
	if (fd < 0) { emit("(open failed)\n"); return; }
	for (;;) {
		long r = sc(SYS_read, fd, (long)buf, (long)sizeof(buf), 0, 0, 0);
		if (r <= 0) break;
		for (int i = 0; i < NOUT; i++)
			if (out[i] >= 0) sc(SYS_write, out[i], (long)buf, r, 0, 0, 0);
	}
	sc(SYS_close, fd, 0, 0, 0, 0, 0);
	emit("\n");
}

struct timespec { long tv_sec; long tv_nsec; };

__attribute__((noreturn))
void _start(void)
{
	/* Best-effort mounts; ignore failures. devtmpfs on /dev was already
	 * auto-mounted by the kernel (CONFIG_DEVTMPFS_MOUNT=y). */
	sc(SYS_mount, (long)"none", (long)"/dev",  (long)"devtmpfs", 0, 0, 0);
	sc(SYS_mount, (long)"none", (long)"/proc", (long)"proc",    0, 0, 0);
	sc(SYS_mount, (long)"none", (long)"/sys",  (long)"sysfs",   0, 0, 0);
	sc(SYS_mount, (long)"none", (long)"/tmp",  (long)"tmpfs",   0, 0, 0);

	/* Collect output channels: stdout first, then the screen explicitly,
	 * then UART. -1 if a device is absent (e.g. no jig -> ttySAC0 open may
	 * still succeed as a device node; that's fine, nobody listens). */
	out[0] = 1;                                   /* /dev/console (stdout) */
	out[1] = open_("/dev/tty0",   O_WRONLY);      /* screen — primary, no jig */
	out[2] = open_("/dev/ttySAC0", O_WRONLY);     /* UART — optional */

	emit("\n\n"
"==========================================================\n"
"  Droidian r7  -  D0 REACHED\n"
"  downstream Linux 4.9.191 (Halium config) booted on\n"
"  Samsung Galaxy Note 10 Lite (SM-N770F, Exynos 9810)\n"
"  via stock S-Boot path (Samsung dt-table)\n"
"  /init (minimal D0 bring-up initramfs) is running.\n"
"==========================================================\n");

	emit("--- kernel ---\n");
	cat("/proc/version", "kernel: ");
	cat("/proc/cmdline", "cmdline: ");
	cat("/proc/meminfo", "meminfo:\n");

	emit(
"==========================================================\n"
"  D0 OK: kernel booted + initramfs /init reached userspace.\n"
"  (This is the D0 probe, NOT Droidian OS — no rootfs/Phosh here.)\n"
"  Looping forever so init never exits. Power off: hold power button.\n"
"  Restore stock: heimdall flash --BOOT boot-preM1.img\n"
"    (or: ./scripts/restore-stock.sh)\n"
"==========================================================\n\n");

	struct timespec ts = { 60, 0 };
	for (;;)
		sc(SYS_nanosleep, (long)&ts, 0, 0, 0, 0, 0);

	__builtin_unreachable();
}