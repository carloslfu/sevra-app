var Sevra = (() => {
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

  // sdk/src/runtime.ts
  var runtime_exports = {};
  __export(runtime_exports, {
    Button: () => Button,
    Canvas: () => Canvas,
    Column: () => Column,
    DatePicker: () => DatePicker,
    Disclosure: () => Disclosure,
    For: () => For,
    Fragment: () => Fragment,
    Grid: () => Grid,
    Image: () => Image,
    Picker: () => Picker,
    Progress: () => Progress,
    Row: () => Row,
    Scroll: () => Scroll,
    Section: () => Section,
    Slider: () => Slider,
    Spacer: () => Spacer,
    Split: () => Split,
    Table: () => Table,
    Tabs: () => Tabs,
    Text: () => Text,
    TextEditor: () => TextEditor,
    TextField: () => TextField,
    Toggle: () => Toggle,
    __flush: () => __flush,
    __initialize: () => __initialize,
    __receive: () => __receive,
    batch: () => n,
    calculate: () => calculate,
    computed: () => O,
    data: () => data,
    draftSignal: () => draftSignal,
    effect: () => effect,
    h: () => h2,
    liveQuery: () => liveQuery,
    mount: () => mount,
    signal: () => a
  });

  // sdk/node_modules/@preact/signals-core/dist/signals-core.mjs
  var t = /* @__PURE__ */ Symbol.for("preact-signals");
  function i() {
    if (e > 1) {
      e--;
      return;
    }
    let t2, i2 = false;
    !(function() {
      let t3 = h;
      h = void 0;
      while (void 0 !== t3) {
        const i3 = t3.S;
        if (i3.v === t3.v) {
          for (let n2 = i3.t; void 0 !== n2; n2 = n2.x) if (n2.i === t3.i) n2.i = i3.i;
        }
        t3 = t3.o;
      }
    })();
    while (void 0 !== r) {
      let n2 = r;
      r = void 0;
      c++;
      while (void 0 !== n2) {
        const o2 = n2.u;
        n2.u = void 0;
        n2.f &= -3;
        if (!(8 & n2.f) && w(n2)) try {
          n2.c();
        } catch (n3) {
          if (!i2) {
            t2 = n3;
            i2 = true;
          }
        }
        n2 = o2;
      }
    }
    c = 0;
    e--;
    if (i2) throw t2;
  }
  function n(t2) {
    if (e > 0) return t2();
    d = ++u;
    e++;
    try {
      return t2();
    } finally {
      i();
    }
  }
  var o;
  var s;
  var r;
  function f(t2) {
    const i2 = o, n2 = s;
    o = void 0;
    s = void 0;
    try {
      return t2();
    } finally {
      o = i2;
      s = n2;
    }
  }
  var h;
  var e = 0;
  var c = 0;
  var u = 0;
  var d = 0;
  var v = 0;
  function l(t2) {
    if (void 0 === o) return;
    let i2 = t2.n;
    if (void 0 === i2 || i2.t !== o) {
      i2 = { i: 0, S: t2, p: o.s, n: void 0, t: o, e: void 0, x: void 0, r: i2 };
      if (void 0 !== o.s) o.s.n = i2;
      o.s = i2;
      t2.n = i2;
      if (32 & o.f) t2.S(i2);
      return i2;
    } else if (-1 === i2.i) {
      i2.i = 0;
      if (void 0 !== i2.n) {
        i2.n.p = i2.p;
        if (void 0 !== i2.p) i2.p.n = i2.n;
        i2.p = o.s;
        i2.n = void 0;
        o.s.n = i2;
        o.s = i2;
      }
      return i2;
    }
  }
  function y(t2, i2) {
    this.v = t2;
    this.i = 0;
    this.n = void 0;
    this.t = void 0;
    this.l = 0;
    this.W = null == i2 ? void 0 : i2.watched;
    this.Z = null == i2 ? void 0 : i2.unwatched;
    this.name = null == i2 ? void 0 : i2.name;
  }
  y.prototype.brand = t;
  y.prototype.h = function() {
    return true;
  };
  y.prototype.S = function(t2) {
    const i2 = this.t;
    if (i2 !== t2 && void 0 === t2.e) {
      t2.x = i2;
      this.t = t2;
      if (void 0 !== i2) i2.e = t2;
      else f(() => {
        var t3;
        null == (t3 = this.W) || t3.call(this);
      });
    }
  };
  y.prototype.U = function(t2) {
    if (void 0 !== this.t) {
      const i2 = t2.e, n2 = t2.x;
      if (void 0 !== i2) {
        i2.x = n2;
        t2.e = void 0;
      }
      if (void 0 !== n2) {
        n2.e = i2;
        t2.x = void 0;
      }
      if (t2 === this.t) {
        this.t = n2;
        if (void 0 === n2) f(() => {
          var t3;
          null == (t3 = this.Z) || t3.call(this);
        });
      }
    }
  };
  y.prototype.subscribe = function(t2) {
    return x(() => {
      const i2 = this.value;
      f(() => t2(i2));
    }, { name: "sub" });
  };
  y.prototype.valueOf = function() {
    return this.value;
  };
  y.prototype.toString = function() {
    return this.value + "";
  };
  y.prototype.toJSON = function() {
    return this.value;
  };
  y.prototype.peek = function() {
    return f(() => this.value);
  };
  Object.defineProperty(y.prototype, "value", { get() {
    const t2 = l(this);
    if (void 0 !== t2) t2.i = this.i;
    return this.v;
  }, set(t2) {
    if (t2 !== this.v) {
      if (c > 100) throw new Error("Cycle detected");
      !(function(t3) {
        if (0 !== e && 0 === c) {
          if (t3.l !== d) {
            t3.l = d;
            h = { S: t3, v: t3.v, i: t3.i, o: h };
          }
        }
      })(this);
      this.v = t2;
      this.i++;
      v++;
      e++;
      try {
        for (let t3 = this.t; void 0 !== t3; t3 = t3.x) t3.t.N();
      } finally {
        i();
      }
    }
  } });
  function a(t2, i2) {
    return new y(t2, i2);
  }
  function w(t2) {
    for (let i2 = t2.s; void 0 !== i2; i2 = i2.n) if (i2.S.i !== i2.i || !i2.S.h() || i2.S.i !== i2.i) return true;
    return false;
  }
  function b(t2) {
    for (let i2 = t2.s; void 0 !== i2; i2 = i2.n) {
      const n2 = i2.S.n;
      if (void 0 !== n2) i2.r = n2;
      i2.S.n = i2;
      i2.i = -1;
      if (void 0 === i2.n) {
        t2.s = i2;
        break;
      }
    }
  }
  function _(t2) {
    let i2, n2 = t2.s;
    while (void 0 !== n2) {
      const t3 = n2.p;
      if (-1 === n2.i) {
        n2.S.U(n2);
        if (void 0 !== t3) t3.n = n2.n;
        if (void 0 !== n2.n) n2.n.p = t3;
      } else i2 = n2;
      n2.S.n = n2.r;
      if (void 0 !== n2.r) n2.r = void 0;
      n2 = t3;
    }
    t2.s = i2;
  }
  function j(t2, i2) {
    y.call(this, void 0, i2);
    this.x = t2;
    this.s = void 0;
    this.g = v - 1;
    this.f = 4;
  }
  j.prototype = new y();
  j.prototype.h = function() {
    this.f &= -3;
    if (1 & this.f) return false;
    if (32 == (36 & this.f)) return true;
    this.f &= -5;
    if (this.g === v) return true;
    this.g = v;
    this.f |= 1;
    if (this.i > 0 && !w(this)) {
      this.f &= -2;
      return true;
    }
    const t2 = o;
    try {
      b(this);
      o = this;
      const t3 = this.x();
      if (16 & this.f || this.v !== t3 || 0 === this.i) {
        this.v = t3;
        this.f &= -17;
        this.i++;
      }
    } catch (t3) {
      this.v = t3;
      this.f |= 16;
      this.i++;
    }
    o = t2;
    _(this);
    this.f &= -2;
    return true;
  };
  j.prototype.S = function(t2) {
    if (void 0 === this.t) {
      this.f |= 36;
      for (let t3 = this.s; void 0 !== t3; t3 = t3.n) t3.S.S(t3);
    }
    y.prototype.S.call(this, t2);
  };
  j.prototype.U = function(t2) {
    if (void 0 !== this.t) {
      y.prototype.U.call(this, t2);
      if (void 0 === this.t) {
        this.f &= -33;
        for (let t3 = this.s; void 0 !== t3; t3 = t3.n) t3.S.U(t3);
      }
    }
  };
  j.prototype.N = function() {
    if (!(2 & this.f)) {
      this.f |= 6;
      for (let t2 = this.t; void 0 !== t2; t2 = t2.x) t2.t.N();
    }
  };
  Object.defineProperty(j.prototype, "value", { get() {
    if (1 & this.f) throw new Error("Cycle detected");
    const t2 = l(this);
    this.h();
    if (void 0 !== t2) t2.i = this.i;
    if (16 & this.f) throw this.v;
    return this.v;
  } });
  function O(t2, i2) {
    return new j(t2, i2);
  }
  function p(t2) {
    const n2 = t2.j;
    t2.j = void 0;
    if ("function" == typeof n2) {
      e++;
      const s2 = o;
      o = void 0;
      try {
        n2();
      } catch (i2) {
        t2.f &= -2;
        t2.f |= 8;
        g(t2);
        throw i2;
      } finally {
        o = s2;
        i();
      }
    }
  }
  function g(t2) {
    for (let i2 = t2.s; void 0 !== i2; i2 = i2.n) i2.S.U(i2);
    t2.x = void 0;
    t2.s = void 0;
    p(t2);
  }
  function S(t2) {
    if (o !== this) throw new Error("Out-of-order effect");
    _(this);
    o = t2;
    this.f &= -2;
    try {
      if (8 & this.f) g(this);
    } finally {
      i();
    }
  }
  function m(t2, i2) {
    this.x = t2;
    this.j = void 0;
    this.s = void 0;
    this.u = void 0;
    this.f = 32;
    this.name = null == i2 ? void 0 : i2.name;
    if (s) s.push(this);
  }
  m.prototype.c = function() {
    const t2 = this.S();
    try {
      if (8 & this.f) return;
      if (void 0 === this.x) return;
      const i2 = this.x();
      if ("function" == typeof i2) this.j = i2;
    } finally {
      t2();
    }
  };
  m.prototype.S = function() {
    if (1 & this.f) throw new Error("Cycle detected");
    this.f |= 1;
    this.f &= -9;
    p(this);
    b(this);
    e++;
    const t2 = o;
    o = this;
    return S.bind(this, t2);
  };
  m.prototype.N = function() {
    if (!(2 & this.f)) {
      this.f |= 2;
      this.u = r;
      r = this;
    }
  };
  m.prototype.d = function() {
    this.f |= 8;
    if (!(1 & this.f)) g(this);
  };
  m.prototype.dispose = function() {
    this.d();
  };
  function x(t2, i2) {
    const n2 = new m(t2, i2);
    try {
      n2.c();
    } catch (t3) {
      n2.d();
      throw t3;
    }
    const o2 = n2.d.bind(n2);
    o2[Symbol.dispose] = o2;
    return o2;
  }

  // sdk/src/runtime.ts
  var owner = null;
  function effect(fn) {
    const dispose = x(fn);
    owner?.push(dispose);
    return dispose;
  }
  var nodes = /* @__PURE__ */ new Map();
  var descriptions = /* @__PURE__ */ new Map();
  var disposers = /* @__PURE__ */ new Map();
  var handlers = /* @__PURE__ */ new Map();
  var requests = /* @__PURE__ */ new Map();
  var subscriptions = /* @__PURE__ */ new Map();
  var edits = /* @__PURE__ */ new Map();
  var draftKeys = /* @__PURE__ */ new WeakMap();
  var patches = /* @__PURE__ */ new Map();
  var outbox = [];
  var requestID = 0;
  var mountID = 0;
  var root = null;
  var initialized = false;
  var draft = {};
  var revision = 0;
  var reading = (value) => value instanceof y ? value.value : typeof value === "function" ? value() : value;
  var changed = (a2, b2) => JSON.stringify(a2) !== JSON.stringify(b2);
  function bounded() {
    if (nodes.size > 512 || outbox.length > 128 || requests.size > 64) throw Error("App resource limit exceeded");
  }
  function send(message) {
    if (message.kind === "draft") {
      const existing = outbox.findIndex((m2) => m2.kind === "draft");
      if (existing >= 0) outbox[existing] = message;
      else outbox.push(message);
    } else outbox.push(message);
    bounded();
  }
  function update(node) {
    patches.set(node.id, { op: "put", node: { ...node, props: { ...node.props }, children: [...node.children] } });
    bounded();
  }
  function h2(type, props, ...children) {
    return { type, props: props || {}, children: children.flat() };
  }
  var Fragment = "column";
  var Column = "column";
  var Row = "row";
  var Grid = "grid";
  var Split = "split";
  var Scroll = "scroll";
  var Section = "section";
  var Text = "text";
  var Button = "button";
  var TextField = "textField";
  var TextEditor = "textEditor";
  var Toggle = "toggle";
  var Picker = "picker";
  var Slider = "slider";
  var DatePicker = "date";
  var Progress = "progress";
  var Table = "table";
  var Tabs = "tabs";
  var Disclosure = "disclosure";
  var Canvas = "canvas";
  var Image = "image";
  var Spacer = "spacer";
  var eventProps = { button: ["onClick"], textField: ["onChange"], textEditor: ["onChange"], toggle: ["onChange"], picker: ["onChange"], slider: ["onChange"], date: ["onChange"], tabs: ["onChange"], disclosure: ["onChange"], table: ["onSelect", "onActivate"], canvas: ["onClick", "onDrop"] };
  function cleanup(id) {
    const node = nodes.get(id);
    if (!node) return;
    for (const dispose of disposers.get(id) || []) dispose();
    for (const child of [...node.children]) cleanup(child);
    for (const key of [...handlers.keys()]) if (key.startsWith(id + ":")) handlers.delete(key);
    disposers.delete(id);
    nodes.delete(id);
    descriptions.delete(id);
    edits.delete(id);
    patches.set(id, { op: "remove", id });
  }
  function mountNode(description, id, depth = 0) {
    if (depth > 24) throw Error("App layout is too deeply nested");
    descriptions.set(id, description);
    const previousOwner = owner, owned = [];
    owner = owned;
    if (description === null || description === false || description === void 0) description = h2(Spacer, {});
    if (typeof description === "string" || typeof description === "number") description = h2(Text, { text: String(description) });
    let expansions = 0;
    while (typeof description.type === "function") {
      if (++expansions > 24) throw Error("Component nesting limit");
      description = description.type({ ...description.props, children: description.children });
    }
    if (!description || typeof description.type !== "string") throw Error("Expected a native component");
    const node = { id, mountID: ++mountID, type: description.type, props: {}, children: [] };
    nodes.set(id, node);
    disposers.set(id, owned);
    const scopes = disposers.get(id);
    for (const [key, value] of Object.entries(description.props)) {
      if (key === "key") continue;
      if (key.startsWith("on")) {
        if (!eventProps[node.type]?.includes(key)) throw Error("Unknown event " + key + " for " + node.type + ". Supported events: " + (eventProps[node.type]?.join(", ") || "none"));
        if (typeof value !== "function") throw Error("Event handlers must be functions");
        handlers.set(id + ":" + key, value);
        continue;
      }
      scopes.push(x(() => {
        const next = reading(value);
        if (changed(node.props[key], next)) {
          node.props[key] = next;
          node.props.editRevision = edits.get(id) || 0;
          update(node);
        }
      }));
    }
    const valueSignal = description.props.value;
    if (valueSignal instanceof y) {
      handlers.set(id + ":bind", (event) => {
        valueSignal.value = event.value;
      });
      const key = draftKeys.get(valueSignal);
      if (key) node.props.draftKey = key;
    }
    const children = description.children.length ? description.children : description.props.children || [];
    scopes.push(x(() => {
      const list = (Array.isArray(children) ? children : [children]).flatMap((child) => {
        const actual = reading(child);
        return Array.isArray(actual) ? actual : [actual];
      }).filter((child) => child !== null && child !== void 0 && child !== false);
      const keys = /* @__PURE__ */ new Set();
      const ids = list.map((child, index) => {
        const key = String(child?.props?.key ?? index);
        if (keys.has(key)) throw Error("Sibling keys must be unique");
        keys.add(key);
        const childID = id + "/" + encodeURIComponent(key);
        if (nodes.has(childID) && descriptions.get(childID) !== child) cleanup(childID);
        if (!nodes.has(childID)) mountNode(child, childID, depth + 1);
        return childID;
      });
      for (const childID of node.children) if (!ids.includes(childID)) cleanup(childID);
      if (changed(node.children, ids)) {
        node.children = ids;
        update(node);
      }
    }));
    update(node);
    owner = previousOwner;
    return id;
  }
  function For(props) {
    const cache = /* @__PURE__ */ new Map();
    const renderer = props.children[0];
    return h2(props.layout || Column, { gap: props.gap ?? 0 }, () => {
      const values = reading(props.each) || [];
      const seen = /* @__PURE__ */ new Set();
      const result = values.map((value) => {
        const key = String(props.by(value));
        if (seen.has(key)) throw Error("List keys must be unique");
        seen.add(key);
        let entry = cache.get(key);
        if (!entry) {
          const item = a(value);
          entry = { value: item, view: renderer(item) };
          entry.view.props = { ...entry.view.props, key };
          cache.set(key, entry);
        } else if (changed(entry.value.peek(), value)) entry.value.value = value;
        return entry.view;
      });
      for (const key of cache.keys()) if (!seen.has(key)) cache.delete(key);
      return result;
    });
  }
  function mount(view) {
    if (root) throw Error("Mount one app root");
    root = mountNode(typeof view === "function" ? h2(view, {}) : view, "root");
  }
  function draftSignal(key, initial) {
    if (!key || key.length > 128) throw Error("Use a short draft key");
    const value = a(Object.hasOwn(draft, key) ? draft[key] : initial);
    draftKeys.set(value, key);
    effect(() => {
      draft[key] = value.value;
      send({ kind: "draft", values: { ...draft } });
    });
    return value;
  }
  function request(method, args) {
    const id = String(++requestID);
    send({ kind: "request", id, method, args });
    return new Promise((resolve, reject) => {
      requests.set(id, { resolve, reject });
      bounded();
    });
  }
  var data = {
    page: (table, options = {}) => request("page", { table, ...options }),
    query: (query) => request("query", query),
    transaction: async (operations, options = {}) => {
      const result = await request("transaction", { operations, revision: options.revision ?? revision, token: options.token || "op-" + Date.now() + "-" + Math.random() });
      revision = Math.max(revision, result.revision);
      return result;
    },
    undo: async (receipt) => request("transaction", { operations: [], undo: receipt.token, revision, token: "undo-" + Date.now() + "-" + Math.random() })
  };
  function liveQuery(query, kind = "page") {
    const value = a({ loading: true, rows: [], revision: 0, error: null });
    const id = "s" + ++requestID;
    subscriptions.set(id, value);
    owner?.push(() => {
      subscriptions.delete(id);
      send({ kind: "unsubscribe", id });
    });
    effect(() => {
      send({ kind: "subscribe", id, method: kind, args: reading(query) });
      value.value = { ...value.peek(), loading: true };
    });
    return value;
  }
  function calculate(expression, values = {}) {
    return request("calculate", { expression, values });
  }
  function __initialize(state) {
    if (initialized) throw Error("Runtime already initialized");
    initialized = true;
    draft = state.draft || {};
    revision = state.revision || 0;
  }
  function __receive(messages) {
    n(() => {
      for (const message of messages) {
        if (message.kind === "event") {
          if (!nodes.has(message.node) || nodes.get(message.node).mountID !== message.mountID) continue;
          edits.set(message.node, message.editRevision || 0);
          const bound = handlers.get(message.node + ":bind");
          if (bound && message.event === "change") bound(message);
          const handler = handlers.get(message.node + ":" + message.handler);
          if (handler) handler(message);
        } else if (message.kind === "result") {
          const pending = requests.get(message.id);
          if (!pending) continue;
          requests.delete(message.id);
          if (message.error) pending.reject(Error(message.error));
          else pending.resolve(message.value);
        } else if (message.kind === "subscription") {
          const value = subscriptions.get(message.id);
          if (!value) continue;
          revision = Math.max(revision, message.value?.revision || 0);
          value.value = message.error ? { ...value.peek(), loading: false, error: message.error } : { ...message.value, loading: false, error: null };
        } else if (message.kind === "revision") revision = message.revision;
      }
    });
  }
  function __flush() {
    const result = { version: 1, root, patches: [...patches.values()], messages: outbox };
    patches.clear();
    outbox = [];
    return result;
  }
  return __toCommonJS(runtime_exports);
})();
