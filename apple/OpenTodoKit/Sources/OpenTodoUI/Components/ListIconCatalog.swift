// The icons a list can pick from in the list editor (`Tasks/ListEditor.swift`):
// SF Symbols (drawn in the list's colour) and emoji, each by category. Any
// other emoji, or a character or two, can be typed in (`ListIcon.custom`).
//
// Every symbol here has to exist on the oldest system we run on (macOS 26 /
// iOS 26): `ListIconCatalogTests` checks them all, so a typo shows up as a
// failing test, not as an empty square.

struct ListIconCategory: Identifiable, Hashable {
    var name: String
    var items: [String]
    var id: String { name }
}

enum ListIconCatalog {
    static let symbols: [ListIconCategory] = [
        ListIconCategory(name: "常用", items: [
            "list.bullet", "checklist", "checkmark.circle", "star", "flag", "bookmark", "pin", "bell",
            "tray", "archivebox", "folder", "doc.text", "calendar", "clock", "lightbulb", "target",
            "flame", "bolt", "heart", "tag", "paperplane", "link", "square.stack", "rectangle.stack",
        ]),
        ListIconCategory(name: "工作", items: [
            "briefcase", "laptopcomputer", "desktopcomputer", "keyboard", "terminal", "chart.bar",
            "chart.pie", "chart.line.uptrend.xyaxis", "building.2", "person.2", "person.3", "envelope",
            "phone", "video", "paperclip", "pencil", "highlighter", "hammer", "wrench.and.screwdriver",
            "gearshape", "megaphone", "printer", "signature", "doc.on.clipboard", "cube", "server.rack",
        ]),
        ListIconCategory(name: "学习", items: [
            "book", "books.vertical", "book.closed", "text.book.closed", "character.book.closed",
            "graduationcap", "brain.head.profile", "brain", "atom", "flask", "testtube.2", "function",
            "sum", "x.squareroot", "globe", "character.bubble", "pencil.and.ruler", "ruler", "backpack",
            "studentdesk", "magnifyingglass", "puzzlepiece", "quote.opening", "abc",
        ]),
        ListIconCategory(name: "生活", items: [
            "house", "cart", "bag", "basket", "bed.double", "sofa", "washer", "fork.knife",
            "cup.and.saucer", "frying.pan", "refrigerator", "lamp.desk", "pawprint", "dog", "cat",
            "figure.2.and.child.holdinghands", "gift", "birthday.cake", "cross.case", "pills",
            "stethoscope", "tshirt", "key", "shippingbox", "scissors", "trash", "lightbulb.2", "powerplug",
        ]),
        ListIconCategory(name: "运动", items: [
            "figure.run", "figure.walk", "figure.yoga", "figure.mind.and.body", "figure.hiking",
            "figure.pool.swim", "figure.outdoor.cycle", "bicycle", "dumbbell", "soccerball", "basketball",
            "tennis.racket", "figure.badminton", "figure.skiing.downhill", "sportscourt", "trophy",
            "medal", "stopwatch", "heart.text.square", "drop", "moon.zzz", "bed.double.circle",
        ]),
        ListIconCategory(name: "出行", items: [
            "airplane", "car", "tram", "bus", "sailboat", "ferry", "scooter", "fuelpump", "map",
            "mappin.and.ellipse", "location", "signpost.right", "suitcase", "suitcase.rolling",
            "globe.asia.australia", "globe.americas", "tent", "mountain.2", "beach.umbrella",
            "ticket", "building.columns", "camera", "binoculars", "parkingsign",
        ]),
        ListIconCategory(name: "爱好", items: [
            "paintpalette", "paintbrush", "pencil.and.scribble", "music.note", "music.mic", "guitars",
            "pianokeys", "headphones", "mic", "gamecontroller", "film", "tv", "photo", "theatermasks",
            "dice", "popcorn", "sparkles", "camera.aperture", "book.pages", "leaf", "scissors.badge.ellipsis",
            "wand.and.stars",
        ]),
        ListIconCategory(name: "财务", items: [
            "dollarsign.circle", "yensign.circle", "eurosign.circle", "creditcard", "banknote",
            "wallet.pass", "giftcard", "chart.line.downtrend.xyaxis", "percent", "bitcoinsign.circle",
            "building.columns.circle", "storefront", "cart.badge.plus", "receipt", "doc.text.magnifyingglass",
            "chart.bar.xaxis",
        ]),
        ListIconCategory(name: "自然", items: [
            "sun.max", "moon", "moon.stars", "cloud", "cloud.rain", "cloud.sun", "snowflake", "wind",
            "umbrella", "rainbow", "leaf", "tree", "camera.macro", "laurel.leading", "drop", "flame",
            "tortoise", "hare", "fish", "bird", "ladybug", "ant", "lizard", "globe.europe.africa",
        ]),
        ListIconCategory(name: "符号", items: [
            "circle", "square", "triangle", "diamond", "hexagon", "seal", "shield", "crown",
            "star.circle", "heart.circle", "bolt.circle", "exclamationmark.triangle", "questionmark.circle",
            "info.circle", "infinity", "number", "at", "sparkle", "asterisk", "plus.circle", "lock",
            "eye", "hand.thumbsup", "face.smiling",
        ]),
    ]

    static let emoji: [ListIconCategory] = [
        ListIconCategory(name: "常用", items: [
            "📋", "📌", "⭐️", "🎯", "✅", "💡", "🔥", "📅", "🗂️", "📝", "🔖", "🏷️",
            "📥", "📤", "⏰", "🔔", "🚩", "💯",
        ]),
        ListIconCategory(name: "工作", items: [
            "💼", "💻", "🖥️", "⌨️", "📊", "📈", "📉", "📁", "📎", "✏️", "🖊️", "📞",
            "📧", "🗓️", "🧾", "🏢", "🤝", "📣", "⚙️", "🔧", "🛠️", "🧑‍💻", "📦", "🗃️",
        ]),
        ListIconCategory(name: "学习", items: [
            "📚", "📖", "🎓", "🧠", "🔬", "🧪", "🧮", "📐", "🌍", "🗣️", "✍️", "🎒",
            "🏫", "📓", "🔤", "🔭", "🧑‍🏫", "📜",
        ]),
        ListIconCategory(name: "生活", items: [
            "🏠", "🛒", "🧹", "🧺", "🛏️", "🪴", "🐶", "🐱", "👶", "👨‍👩‍👧", "🎁", "💊",
            "🏥", "🦷", "💇", "👕", "🔑", "🧴", "🛁", "🧸", "💐", "🕯️",
        ]),
        ListIconCategory(name: "运动", items: [
            "🏃", "💪", "🧘", "🚴", "🏊", "⚽️", "🏀", "🎾", "🏸", "🏓", "⛰️", "🥾",
            "🏋️", "⛷️", "🧗", "🤸", "😴", "💧",
        ]),
        ListIconCategory(name: "饮食", items: [
            "🍎", "🥗", "🍳", "🍜", "🍕", "🍰", "☕️", "🍵", "🍷", "🥤", "🍚", "🥦",
            "🍓", "🧁", "🍱", "🥟", "🍺", "🥛",
        ]),
        ListIconCategory(name: "出行", items: [
            "✈️", "🚗", "🚆", "🚲", "🗺️", "🧳", "🏖️", "🏕️", "🏔️", "🚢", "🎫", "🏨",
            "🚇", "🛵", "⛽️", "🗼", "🏯", "🌏",
        ]),
        ListIconCategory(name: "爱好", items: [
            "🎨", "🎵", "🎸", "🎹", "🎮", "🎬", "📷", "🎲", "🧩", "🎤", "🎧", "📺",
            "🎭", "🧶", "🪡", "🎻", "📸", "🎣",
        ]),
        ListIconCategory(name: "财务", items: [
            "💰", "💳", "💵", "🏦", "🪙", "🧧", "💎", "🛍️", "💹", "🧾", "🐷", "📒",
        ]),
        ListIconCategory(name: "自然", items: [
            "🌱", "🌸", "🌻", "🌳", "🍀", "🌙", "☀️", "🌈", "❄️", "🌊", "🍁", "🌵",
            "🐟", "🦋", "🐝", "🌷", "⛅️", "🌕",
        ]),
        ListIconCategory(name: "心情", items: [
            "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "😀", "😎", "🥳", "🤔",
            "🙏", "👍", "🎉", "✨", "⚡️", "❗️", "❓", "💤", "🌟", "🫶",
        ]),
    ]
}
