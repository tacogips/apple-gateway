# Bounded Notes write target lookup

Attachment creation, body replacement, deletion and moves resolve a note by exact
ID rather than enumerate the entire library. The note identity, lock state and
bounded container/account ownership are verified before the existing mutation
marker. Move destinations additionally use exact folder ID and account validation.
The native mutation commands and unknown-outcome/no-replay policy are unchanged.

Executable offline JXA fixtures reject account/folder/note enumeration, verify
one exact lookup/one marker/one mutation, and reject missing, locked, mismatched,
cyclic or foreign targets before dispatch. Existing uncertain-timeout tests ensure
mutations are not replayed. No live Notes write is used for validation.

Creation operations still select a destination account/folder and folder creation
still checks siblings for idempotency; neither write template enumerates notes.
This patch does not claim that every service-level folder listing is constant-time.
