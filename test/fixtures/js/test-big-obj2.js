f(obj.prototype, {
  p0: mk(k0),
  p1: mk(k1),
  p2: mk(k2),
  p3: {
    __proto__: null,
    enumerable: false,
    get() {
      return (this[kState] & k3) !== 0 ? this[kVal3] : null;
    },
    set(value) {
      if (value) {
        this[kVal3] = value;
        this[kState] |= k3;
      } else {
        this[kState] &= ~k3;
      }
    },
  },
  p4: {
    __proto__: null,
    enumerable: false,
    get() {
      return (this[kState] & k4) !== 0 ? this[kVal4] : null;
    },
    set(value) {
      if (value) {
        this[kVal4] = value;
        this[kState] |= k4;
      } else {
        this[kState] &= ~k4;
      }
    },
  },
  p5: {
    __proto__: null,
    enumerable: false,
    get() {
      return (this[kState] & k5) !== 0 ? this[kVal5] : null;
    },
    set(value) {
      if (value) {
        this[kVal5] = value;
        this[kState] |= k5;
      } else {
        this[kState] &= ~k5;
      }
    },
  },
  p6: {
    __proto__: null,
    enumerable: false,
    get() {
      return (this[kState] & k6) !== 0 ? this[kVal6] : null;
    },
    set(value) {
      if (value) {
        this[kVal6] = value;
        this[kState] |= k6;
      } else {
        this[kState] &= ~k6;
      }
    },
  },
  p7: {
    __proto__: null,
    enumerable: false,
    get() {
      return (this[kState] & k7) !== 0 ? this[kVal7] : null;
    },
    set(value) {
      if (value) {
        this[kVal7] = value;
        this[kState] |= k7;
      } else {
        this[kState] &= ~k7;
      }
    },
  },
  p8: {
    __proto__: null,
    enumerable: false,
    get() {
      return (this[kState] & k8) !== 0 ? this[kVal8] : null;
    },
    set(value) {
      if (value) {
        this[kVal8] = value;
        this[kState] |= k8;
      } else {
        this[kState] &= ~k8;
      }
    },
  },
  p9: {
    __proto__: null,
    enumerable: false,
    get() {
      return (this[kState] & k9) !== 0 ? this[kVal9] : null;
    },
    set(value) {
      if (value) {
        this[kVal9] = value;
        this[kState] |= k9;
      } else {
        this[kState] &= ~k9;
      }
    },
  }
});
