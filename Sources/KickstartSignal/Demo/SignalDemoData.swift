//
// SignalDemoData.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation

/// A small roadmap for a fictional reading app used by the Signal example.
/// Includes French and Spanish feedback for trying inline translation.
@available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
enum SignalDemoData {
    static let offlineID = "ksreq_" + String(repeating: "a", count: 32)
    static let foldersID = "ksreq_" + String(repeating: "b", count: 32)
    static let highlightsID = "ksreq_" + String(repeating: "c", count: 32)
    static let widgetsID = "ksreq_" + String(repeating: "d", count: 32)
    static let startDate = Date(timeIntervalSince1970: 1_788_220_800)

    static let requests = [
        SignalRequest(
            id: offlineID, creationOrder: 2,
            title: "Read saved articles offline",
            description: """
            I save articles before my train journey, but the connection drops in the tunnels. \
            Please download the text and images so I can keep reading without a signal.

            An option to download only over Wi-Fi would help with my data allowance.
            """,
            status: .inProgress, voteCount: 128,
            updatedAt: startDate.addingTimeInterval(864_000)
        ),
        SignalRequest(
            id: foldersID, creationOrder: 3,
            title: "Organiser ma bibliothèque en dossiers",
            description: """
            Mes recettes, mes recherches pour le travail et mes lectures du week-end sont toutes mélangées. \
            J'aimerais pouvoir créer des dossiers et déplacer plusieurs articles à la fois.
            """,
            status: .planned, voteCount: 76,
            updatedAt: startDate.addingTimeInterval(691_200)
        ),
        SignalRequest(
            id: highlightsID, creationOrder: 1,
            title: "Export highlights as Markdown",
            description: """
            Let me export my highlights with the article title and a link to the original, \
            ready to paste into my study notes.
            """,
            status: .completed, voteCount: 43,
            updatedAt: startDate.addingTimeInterval(950_400)
        ),
        SignalRequest(
            id: widgetsID, creationOrder: 4,
            title: "A widget for my reading queue",
            description: "Show the next few unread articles on my Home Screen so I remember to make time for them.",
            status: .open, voteCount: 9,
            updatedAt: startDate.addingTimeInterval(1_382_400)
        )
    ]

    static let comments: [String: [SignalComment]] = [
        offlineID: [
            comment("1", """
            This would be great for flights too. I often open a saved article after boarding and find it \
            hasn't loaded.
            """, day: 3),
            comment("2", """
            We're working on this now. Saved articles will include their images, with a Wi-Fi-only download \
            option in Settings. Your existing library will download automatically when you enable offline reading.
            """, developer: true, day: 5),
            comment("3", """
            Great news. I'd also appreciate a way to see how much space my downloads are using.
            """, day: 7),
            comment("f", """
            Could downloaded articles have a small indicator in the library? I'd like to check everything \
            is ready before I leave home.
            """, day: 8),
            comment("0", """
            Please let me remove a download without deleting the saved article. My phone is usually short \
            on storage.
            """, day: 9),
            comment("4", """
            Please keep the article text available if an image fails to download. I'd rather read without \
            pictures than lose the whole article.
            """, day: 10)
        ],
        foldersID: [
            comment("5", """
            Tener una carpeta para cada proyecto me ayudaría mucho. Sería útil poder guardar un artículo \
            en varias carpetas.
            """, day: 4),
            comment("12", """
            Un article pourra figurer dans plusieurs dossiers sans créer de copies. Vous pourrez toujours \
            tout retrouver dans Tous les articles.
            """, developer: true, day: 5),
            comment("6", """
            ¡Buena idea!
            """, day: 6),
            comment("13", """
            Please include a way to rename folders. My project names tend to change once I start researching.
            """, day: 7),
            comment("7", """
            Moving several articles together would be really useful. I have a few hundred saved links to sort \
            and wouldn't want to move them one at a time.
            """, day: 8),
            comment("14", """
            An Unfiled view would help me finish organizing. Otherwise I'll lose track of which articles \
            I haven't put in a folder yet.
            """, day: 8)
        ],
        highlightsID: [
            comment("8", """
            Including the source link would save me so much time when I'm putting together references.
            """, day: 2),
            comment("9", """
            Shipped in version 2.4! Open an article, choose Share, then Export Highlights. The Markdown \
            includes the source link.
            """, developer: true, day: 9),
            comment("a", """
            Just tried it with my course reading. The formatting is exactly what I needed, thank you!
            """, day: 10),
            comment("15", """
            The source links work well in my notes app. I can finally get back to the full article \
            without searching for it again.
            """, day: 10),
            comment("b", """
            This works nicely with Obsidian. Having the article title above the quotes makes my notes much \
            easier to scan.
            """, day: 11),
            comment("16", """
            Exported a long article this morning and all my highlights stayed in reading order. This \
            will save me a lot of copying and pasting.
            """, day: 11)
        ],
        widgetsID: [
            comment("c", """
            A small widget with just the next article would be enough for me. I'd put it beside my calendar \
            as a reminder to take a reading break.
            """, day: 13),
            comment("d", """
            Could the larger widget show estimated reading times? It's helpful to know what I can finish \
            while waiting for the bus.
            """, day: 14),
            comment("17", """
            Tapping an article should open it straight away. I'd rather skip the library when I only \
            have a few minutes to read.
            """, day: 14),
            comment("18", """
            Thanks for these ideas. We're looking at a single-article widget and a larger queue, with \
            reading times on both. Folder selection is on our list to explore too.
            """, developer: true, day: 15),
            comment("e", """
            I'd love to choose which folder the widget uses, so my weekend reading doesn't get mixed in \
            with work articles.
            """, day: 16),
            comment("19", """
            Please move on to the next unread article after I finish one. A queue that updates itself \
            would make the widget much more useful.
            """, day: 16)
        ]
    ]

    /// Creates a sample comment with a stable ID and a date relative to the sample board.
    private static func comment(
        _ identifier: String, _ body: String, developer: Bool = false, day: Double
    ) -> SignalComment {
        SignalComment(
            id: "kscom_" + String(repeating: identifier, count: 32).prefix(32), body: body, isDeveloper: developer,
            createdAt: startDate.addingTimeInterval(day * 86_400)
        )
    }

    /// Creates an independent, in-memory client populated with the sample requests and comments.
    @MainActor
    static func makeClient() -> SignalClient {
        SignalClient.demo(requests: requests, comments: comments)
    }
}
