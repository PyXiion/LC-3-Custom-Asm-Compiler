module lexer;

import std.stdio;
import std.conv;
import std.uni;
import std.format;

enum LexKey {
  NONE = 0, 
  NUM, IDENTIFICATOR, STRING, CHAR,
  COLON, MINUS, PLUS, COMMA, DOT, SEPARATOR,

  // directives               8bit 16bit 32bit
  INCLUDE, ORG, ASCII, ASCIZ, BYTE, INT, LONG, // FLOAT, DOUBLE,

  MACROSTART, MACROEND,

  EOF,

  // Instructions
  BR,         // branch
  ADD,        // add
  LD,         // load
  ST,         // store
  JSR,        // jump register
  AND,        // bitwise and
  LDR,        // load register
  STR,        // store register
  RTI,        // unused
  NOT,        // bitwise not
  LDI,        // load indirect
  STI,        // store indirect
  JMP,        // jump
  RES,        // reversed (unused)
  LEA,        // load effective address
  TRAP,        // execute trap
  RET,
  JSRR
}
enum Reg : byte {
  R0 = 0, R1, R2, R3, R4, R5, R6, R7
}

shared static this() {
  SYMBOLS = [
    // '.': LexKey.DOT, 
    ',': LexKey.COMMA, ':': LexKey.COLON, '+': LexKey.PLUS, '-': LexKey.MINUS,
    '\n': LexKey.SEPARATOR
  ];
  WORDS = [
    ".INCLUDE": LexKey.INCLUDE, ".ORG": LexKey.ORG,
    ".ASCII": LexKey.ASCII, ".ASCIZ": LexKey.ASCIZ,
    ".BYTE": LexKey.BYTE, ".INT": LexKey.INT, ".LONG": LexKey.LONG,
    ".MACRO": LexKey.MACROSTART, ".MEND": LexKey.MACROEND,
    
    "BR": LexKey.BR,   "ADD": LexKey.ADD,  "LD": LexKey.LD,     "ST": LexKey.ST,
    "JSR": LexKey.JSR,  "AND": LexKey.AND, "LDR": LexKey.LDR,   "STR": LexKey.STR,
    "RTI": LexKey.RTI,  "NOT": LexKey.NOT, "LDI": LexKey.LDI,   "STI": LexKey.STI,
    "RES": LexKey.RES,  "JMP": LexKey.JMP, "LEA": LexKey.LEA,  "TRAP": LexKey.TRAP,
    "RET": LexKey.RET, "JSRR":LexKey.JSRR,

    // variables of BR
    "BRN": LexKey.BR,   "BRZ": LexKey.BR,  "BRP": LexKey.BR,   "BRZP": LexKey.BR,
    "BRNP": LexKey.BR,  "BRNZ": LexKey.BR,"BRNZP": LexKey.BR
  ];
}

LexKey[char] SYMBOLS;
LexKey[string] WORDS;

struct LexValue {
  enum ValType {
    NONE,
    STRING,
    INT,
    REGISTER
  }
  ValType type = ValType.NONE;
  
  string str;
  int i;

  void set(int i) {
    type = ValType.INT;
    this.i = i;
  }
  void set(string str) {
    type = ValType.STRING;
    this.str = str;
  }
  void set(Reg r) {
    type = ValType.REGISTER;
    this.i = r;
  }
  void clear() {
    type = ValType.NONE;
    str = "";
  }

  bool opCast(T : bool)() const {
    return type != ValType.NONE;
  }
  string asStr() {
    switch (type) {
      case ValType.INT: return to!string(i); break;
      case ValType.STRING: return str; break;
      case ValType.REGISTER: return to!string(cast(Reg) i);
      default: return "0"; break;
    }
  }
}

bool isAlpha(char c) {
  return ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')) || (c >= '0' && c <= '9') || c == '_';
}

class Lexer {
  private string code;

  private size_t index = 0;
  private char current;

  private LexKey sym = LexKey.NONE;
  private LexValue value;

  private int line, cur;


  private void error(string msg) {
    import core.stdc.stdlib;
    import std.format;
    writeln(format("Lexer error at line %d, pos %d.\n" ~
                   "%s", getLine, getCur, msg));
    exit(1);
  }
  private void getc() {
    if (index == code.length) {
      current = 0;
      return;
    }

    current = code[index++];

    if (current == '\n') {
      line++;
      cur = -1;
    }
    else {
      cur++;
    }
  }

  void setCode(string code) {
    this.code = code;
    index = 0;
    getc();
  }
  LexValue getValue() const {
    return value;
  }
  LexKey getSym() const {
    return sym;
  }
  int getLine() const {
    return line;
  }
  int getCur() const {
    return cur;
  }

  LexKey next_token() {
    sym = LexKey.NONE;
    value.clear();
    while (sym == LexKey.NONE) {
      // end of file
      if (current == 0) {
        sym = LexKey.EOF;
      }
      // skip spaces
      else if (current == ' ' || current == '\t' || current == '\r') {
        getc();
      }
      // commentary
      else if (current == ';') {
        while (current != '\n' && current != 0) // skip all to end of line
          getc();
      }
      // one symbol tokens
      else if (current in SYMBOLS) {
        sym = SYMBOLS[current];
        getc();
      }
      // char
      else if (current == '\'') {
        sym = LexKey.CHAR;
        getc();
        char c = current;
        getc();
        if (current != '\'')
          goto unexpected;
        value.set(c);
        getc();
      }
      // string
      else if (current == '"') {
        sym = LexKey.STRING;
        bool ignoreNext;
        char[] str;
        getc();

        while (true) {
          if (current == '\\' && !ignoreNext) {
            getc();
            ignoreNext = true;
          }
          else if (current == '"' && !ignoreNext) {
            getc();
            break;
          }
          else {
            ignoreNext = false;
            str ~= current;
            getc();
          }
        }
        value.set(to!string(str));
      }
      // dec integers, must lead 1..9 (0 for other)
      else if (current >= '1' && current <= '9') {
        dec_num:
        int val = 0;
        while (current >= '0' && current <= '9') {
          val = val * 10 + (current - '0');
          getc();
        }
        value.set(val);
        sym = LexKey.NUM;
      }
      // hex, bin or oct integer (leading 0)
      else if (current == '0') {
        int val = 0;
        getc(); // ignore 1st, it's always 0
        if (current == 'x' || current == 'X') { // hexadecimal
          getc(); // skip 'x'
          while ((current >= '0' && current <= '9') || (current >= 'a' && current <= 'f') || 
                 (current >= 'A' && current <= 'F')) {
            val *= 16;
            if (current >= '0' && current <= '9')
              val += current - '0';
            else if (current <= 'f')
              val += 10 + current - 'a';
            else
              val += 10 + current - 'F';
            
            getc();
          }
        }
        else if (current == 'b' || current == 'B') { // binary
          getc(); // skib 'b'
          while (current == '0' || current == '1') {
            val = (val << 1) | (current - '0');
            getc();
          }
        }
        else if (current == 'o' || current == 'O') { // octodecimal
          getc();
          while (current >= '0' && current <= '7') {
            val = val * 8 + current - '0';
            getc();
          }
        }
        else {
          goto dec_num;
        }
        value.set(val);
        sym = LexKey.NUM;
      }
      else if (isAlpha(current) || current == '.') {
        char[] ident;
        while (isAlpha(current) || current == '.') {
          ident ~= current;
          getc();
        }
        if (toUpper(ident) in WORDS) {
          sym = WORDS[toUpper(ident)];
        }
        else {
          sym = LexKey.IDENTIFICATOR;
        }
        value.set(to!string(ident));
      }
      else {
      unexpected:
        error("Unexpected symbol: " ~ current ~ format(" (bin: %08b, hex: %x)", current, current));
      }
    }
    return sym;
  }
  
}