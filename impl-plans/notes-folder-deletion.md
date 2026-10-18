# Notes folder deletion

Add an exact account/folder-ID deletion operation to NotesWriting, NotesWriteService, live JXA and the full GraphQL command catalog. Empty-only is the default; explicit allowNonEmpty permits native descendant deletion. Preserve compatibility with custom NotesWriting implementations through an unavailable default. Revalidate account/identity/emptiness in the native command before its write marker. Never issue purge/trash-empty operations or automatically replay uncertain writes.

Verify injected service/GraphQL validation, executable JXA identity/emptiness/descendant-consent contracts, mutation retry classification, package tests and SwiftLint. No live Notes calls. Recovery placement and hierarchy restoration remain native Notes/account policy, not a gateway guarantee. Release/version integration belongs to the release owner.
