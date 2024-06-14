export default {
    0: {
        name: "#root",
        id: 0,
        size: 0,
        slots: [],
        children: [
            {
                mountpoint: true
            }
        ]
    },
    1: {
        name: "counter",
        id: 1,
        size: 4,
        slots: ["count"],
        children: [
            {
                tag: "button",
                attributes: [
                    {
                        name: "style",
                        value: "display: flex; flex-direction: column;"
                    }
                ],
                actions: [
                    {
                        name: "onclick",
                        ref: "increment"
                    }
                ],
                children: [
                    {
                        tag: "span",
                        attributes: [],
                        actions: [],
                        children: [
                            {
                                slot: 0
                            }
                        ]
                    },
                    {
                        tag: "span",
                        attributes: [],
                        actions: [],
                        children: [
                            {
                                mountpoint: true
                            }
                        ]
                    }
                ]
            }
        ]
    },
    2: {
        name: "hello",
        id: 2,
        size: 1,
        slots: [],
        children: [
            "world"
        ]
    }
};