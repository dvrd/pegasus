'use strict';

const {
  Array,
  ArrayIsArray,
  ArrayPrototypeJoin,
  ArrayPrototypeMap,
  ArrayPrototypePush,
  Boolean,
  Int8Array,
  IteratorPrototype,
  Number,
  ObjectDefineProperties,
  ObjectSetPrototypeOf,
  ReflectGetOwnPropertyDescriptor,
  ReflectOwnKeys,
  SafeMap,
  SafeSet,
  StringPrototypeCharAt,
  StringPrototypeCharCodeAt,
  StringPrototypeCodePointAt,
  StringPrototypeIncludes,
  StringPrototypeIndexOf,
  StringPrototypeSlice,
  StringPrototypeStartsWith,
  StringPrototypeToWellFormed,
  Symbol,
  SymbolIterator,
  SymbolToStringTag,
  TypedArrayPrototypeGetBuffer,
  TypedArrayPrototypeGetByteLength,
  TypedArrayPrototypeGetByteOffset,
  decodeURIComponent,
} = primordials;

const { URLPattern } = internalBinding('url_pattern');
const { inspect } = require('internal/util/inspect');
const {
  encodeStr,
  hexTable,
  isHexTable,
} = require('internal/querystring');

const {
  getConstructorOf,
  removeColors,
  kEnumerableProperty,
  kEmptyObject,
  SideEffectFreeRegExpPrototypeSymbolReplace,
  isWindows,
} = require('internal/util');

const {
  platform,
} = require('internal/process/per_thread');

const {
  markTransferMode,
} = require('internal/worker/js_transferable');

const {
  codes: {
    ERR_ARG_NOT_ITERABLE,
    ERR_INVALID_ARG_TYPE,
    ERR_INVALID_ARG_VALUE,
    ERR_INVALID_FILE_URL_HOST,
    ERR_INVALID_FILE_URL_PATH,
    ERR_INVALID_THIS,
    ERR_INVALID_TUPLE,
    ERR_INVALID_URL,
    ERR_INVALID_URL_SCHEME,
    ERR_MISSING_ARGS,
    ERR_NO_CRYPTO,
  },
} = require('internal/errors');
const {
  CHAR_AMPERSAND,
  CHAR_BACKWARD_SLASH,
  CHAR_EQUAL,
  CHAR_FORWARD_SLASH,
  CHAR_LOWERCASE_A,
  CHAR_LOWERCASE_Z,
  CHAR_PERCENT,
  CHAR_PLUS,
  CHAR_COLON,
} = require('internal/constants');
const path = require('path');
const { Buffer } = require('buffer');

const {
  validateFunction,
  validateObject,
  kValidateObjectAllowObjects,
} = require('internal/validators');

const { percentDecode } = require('internal/data_url');

const querystring = require('querystring');

const bindingUrl = internalBinding('url');

const FORWARD_SLASH = /\//g;

const contextForInspect = Symbol('context');

// `unsafeProtocol`, `hostlessProtocol` and `slashedProtocol` is
// deliberately moved to `internal/url` rather than `url`.
// Workers does not bootstrap URL module. Therefore, `SafeSet`
// is not initialized on bootstrap. This case breaks the
// test-require-delete-array-iterator test.

// Protocols that can allow "unsafe" and "unwise" chars.
const unsafeProtocol = new SafeSet([
  'javascript',
  'javascript:',
]);
// Protocols that never have a hostname.
const hostlessProtocol = new SafeSet([
  'javascript',
  'javascript:',
]);
// Protocols that always contain a // bit.
const slashedProtocol = new SafeSet([
  'http',
  'http:',
  'https',
  'https:',
  'ftp',
  'ftp:',
  'gopher',
  'gopher:',
  'file',
  'file:',
  'ws',
  'ws:',
  'wss',
  'wss:',
]);

const updateActions = {
  kProtocol: 0,
  kHost: 1,
  kHostname: 2,
  kPort: 3,
  kUsername: 4,
  kPassword: 5,
  kPathname: 6,
  kSearch: 7,
  kHash: 8,
  kHref: 9,
};
let blob;
let cryptoRandom;

function lazyBlob() {
  blob ??= require('internal/blob');
  return blob;
}

function lazyCryptoRandom() {
  try {
    cryptoRandom ??= require('internal/crypto/random');
  } catch {
    // If Node.js built without crypto support, we'll fall
    // through here and handle it later.
  }
  return cryptoRandom;
}

// This class provides the internal state of a URL object. An instance of this
// class is stored in every URL object and is accessed internally by setters
// and getters. It roughly corresponds to the concept of a URL record in the
// URL Standard, with a few differences. It is also the object transported to
// the C++ binding.
// Refs: https://url.spec.whatwg.org/#concept-url
class URLContext {
  // This is the maximum value uint32_t can get.
  // Ada uses uint32_t(-1) for declaring omitted values.
  static #omitted = 4294967295;

  href = '';
  protocol_end = 0;
  username_end = 0;
  host_start = 0;
  host_end = 0;
  pathname_start = 0;
  search_start = 0;
  hash_start = 0;
  port = 0;
  /**
   * Refers to `ada::scheme::type`
   *
   * enum type : uint8_t {
   *   HTTP = 0,
   *   NOT_SPECIAL = 1,
   *   HTTPS = 2,
   *   WS = 3,
   *   FTP = 4,
   *   WSS = 5,
   *   FILE = 6
   * };
   * @type {number}
   */
  scheme_type = 1;

  get hasPort() {
    return this.port !== URLContext.#omitted;
  }

  get hasSearch() {
    return this.search_start !== URLContext.#omitted;
  }

  get hasHash() {
    return this.hash_start !== URLContext.#omitted;
  }
}
