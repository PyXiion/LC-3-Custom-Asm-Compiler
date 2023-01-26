.org 0x3000  ; Starting address.

.MACRO getc
  trap 0x20
.MEND
.MACRO out
  trap 0x21
.MEND
.MACRO puts
  trap 0x22
.MEND
.MACRO in
  trap 0x23
.MEND
.MACRO putsp
  trap 0x24
.MEND
.MACRO halt
  trap 0x25
.MEND

lea r0, hello_world
puts
halt

hello_world:    .asciz "Hello world!"