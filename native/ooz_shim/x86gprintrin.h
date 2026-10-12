// GCC 8 does not know this header yet. Without it ooz defines its own _rotl,
// which clashes with the one from MinGW's stdlib.h; this empty header
// prevents that.
#pragma once
