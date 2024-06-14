type Ptr<_T> = number;
type ManyPtr<T> = Ptr<T>;

type Part = {
    slot: number
} | string;

type Attribute = {
    name: string;
    value: Part;
};

type Action = {
    name: string;
    ref: string;
};

type Element = {
    tag: "button";
    attributes: Attribute[];
    actions: Action[];
    children: Child[];
};

type Mountpoint = {
    mountpoint: true;
};

type Child = Element | Part | Mountpoint;

type Template = {
    name: string;
    id: number;
    size: number;
    slots: string[];
    children: Child[];
};

type Templates = Record<number, Template>;

export function readCString(buf: ArrayBuffer, ptr: number) {
    const mem = new Uint8Array(buf, ptr);
    const decoder = new TextDecoder();
    let i = 0;
    while (mem[i] != 0 || i > mem.length) {
        i += 1;
    }
    return decoder.decode(mem.slice(0, i));
}

export function writeZigUtf8Bytes(buf: ArrayBuffer, ptr: number, str: string, maxBufferSize: number, doZeroSentinel: boolean) {
    const mem = new Uint8Array(buf, ptr);
    const bytes = new TextEncoder().encode(str);
    const numBytesToWrite = Math.min(bytes.byteLength, maxBufferSize, mem.byteLength);
    mem.set(bytes.slice(0, numBytesToWrite), 0);
    if (doZeroSentinel) mem[bytes.byteLength] = 0;
    return numBytesToWrite;
}

interface TypedArrayConstructor<T> {
    readonly prototype: T;
    new(length: number): T;
    new(array: ArrayLike<number> | ArrayBufferLike): T;
    new(buffer: ArrayBufferLike, byteOffset?: number, length?: number): T;
}

function derefManyPointer<Ctr extends TypedArrayConstructor<unknown>>(buf: ArrayBuffer, num: number, ptr: ManyPtr<any>, arr: Ctr): Ctr extends TypedArrayConstructor<infer X> ? X : never {
    return new arr(buf, ptr, num) as any;
}

export class SubMount {
    constructor(
        public readonly childOf: number | null,
        public readonly siblingIdx: number
    ) { };
}

export class Snippet {
    children: Node[];
    subMounts: SubMount[];

    protected constructor(
        public readonly mountpoint: HTMLElement,
        public readonly template: Template,
        public readonly slots: string[]
    ) {
        this.children = [];
        this.subMounts = [];
    }

    resolveInitialPart(part: Part) {
        if (typeof part === "string") return part;
        return this.slots[part.slot];
    }

    createChild(parentId: number | null, siblingIdx: number, child: Child): Node | null {
        if (typeof child === "object" && "tag" in child) {
            const elem = document.createElement(child.tag);
            for (const attribute of child.attributes) {
                elem.setAttribute(attribute.name, this.resolveInitialPart(attribute.value));
            }
            for (const action of child.actions) {
                // todo
                action; // silence unused variable warning
            }
            this.children.push(elem);
            this.createAppendChildren(elem, this.children.length - 1, child.children);
            return elem;
        } else if (typeof child === "object" && "mountpoint" in child) {
            this.subMounts.push(new SubMount(parentId, siblingIdx));
            return null; // virtual child
        } else {
            const text = document.createTextNode(this.resolveInitialPart(child));
            this.children.push(text);
            return text;
        }
    }

    createAppendChildren(root: HTMLElement, parentId: number | null, children: Child[]) {
        for (let i = 0; i < children.length; i++) {
            const child = children[i];
            const node = this.createChild(parentId, i, child);
            if (node !== null) { // is not virtual child (can be immediately appended)?
                root.appendChild(node);
            }
        }
    }

    static mountTemplateToDom(
        mountpoint: HTMLElement,
        template: Template,
        slots: string[]
    ) {
        const mounting = new Snippet(mountpoint, template, slots);
        mounting.createAppendChildren(mountpoint, null, template.children);
        return mounting;
    }
}

export class ZodiacState {
    protected _id: number = 0;

    snippets: Map<number, Snippet> = new Map;

    registerSnippet(snippet: Snippet) {
        this.snippets.set(this._id, snippet);
        this._id += 1;
        return this._id - 1;
    }
}

window.onload = (async () => {
    const templates: Templates = (await import("/templates.js?url")).default as any;
    const appElem = document.querySelector("#app") as HTMLElement;

    const rootSnippet = Snippet.mountTemplateToDom(appElem, templates[0], []);

    const state = new ZodiacState;
    state.registerSnippet(rootSnippet);

    const testBinary = await fetch("/test.wasm");
    let wasm: WebAssembly.WebAssemblyInstantiatedSource;
    wasm = await WebAssembly.instantiateStreaming(testBinary, {
        env: {
            mount(mountpointSnippetId: number, subMountpointId: number, templateId: number, numSlots: number, slotsPtr: ManyPtr<ManyPtr<number>>) {
                const mountpointSnippet = state.snippets.get(mountpointSnippetId);
                if (mountpointSnippet === undefined)
                    return console.error("Invalid mountpoint snippet id: ", mountpointSnippetId);

                const subMountpoint = mountpointSnippet.subMounts[subMountpointId];
                if (subMountpoint === undefined)
                    return console.error("Invalid sub-mountpount id: ", subMountpointId);

                const mountElement = subMountpoint.childOf === null ? mountpointSnippet.mountpoint : mountpointSnippet.children[subMountpoint.childOf];
                if (mountElement === undefined)
                    return console.error("Invalid sub-mountpoint parent id: ", subMountpoint.childOf);

                const template = templates[templateId];
                const mem = wasm.instance.exports.memory as WebAssembly.Memory;
                const strSlots = [];
                if (numSlots !== 0) {
                    const pointers = derefManyPointer(mem.buffer, numSlots, slotsPtr, Uint32Array);
                    for (const pointer of pointers) {
                        const str = readCString(mem.buffer, pointer);
                        strSlots.push(str);
                    }
                }
                const snippet = Snippet.mountTemplateToDom(mountElement as HTMLElement, template, strSlots);
                state.registerSnippet(snippet);
            }
        }
    });

    if (typeof wasm.instance.exports.init === "function") {
        wasm.instance.exports.init();
    }
});