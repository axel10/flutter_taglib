#ifndef TAGLIB_CONFIG_H
#define TAGLIB_CONFIG_H

/* Defined if your compiler supports some byte swap functions */
#if defined(__APPLE__)
#define HAVE_MAC_BYTESWAP 1
#elif defined(_MSC_VER)
#define HAVE_MSC_BYTESWAP 1
#elif defined(__GNUC__)
#define HAVE_GCC_BYTESWAP 1
#endif

/* Defined if your compiler supports ISO _strdup */
#define HAVE_ISO_STRDUP 1

#endif
