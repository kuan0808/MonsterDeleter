# A character that cannot be loaded is named, never replaced by stand-in art

Until now every pack failure fell back to the generated placeholder: coloured silhouettes with
frame numbers on them. A broken install therefore looked finished, and the app was lying about its
own state. It stops. A pack that cannot be loaded is reported with its name and the reason
(`PackLibrary.onLoadFailure` becomes an alert naming the pack, the reason, what the app is wearing
instead and what to do about it), the character that already works stays on, and a launch that has
nothing on yet moves forward to the next character that does load. With no character at all there
is no show: the summon says so and points at the Settings window.

That also takes the placeholder out of the character list. It is no longer something a user can
choose, so `PackEntry` has no placeholder entry and every entry is a folder on disk. It survives in
the two roles that are not user-facing and cannot be served by anything else: the deterministic pack
the autoplay self-test judges its checkpoints against, and the template
`MONSTER_EXPORT_PLACEHOLDER` writes out for someone authoring a character.

## Considered options

- **Keep the fallback and log it.** What we had. A log nobody reads is the same as silence, and the
  show that ran was not the show the user chose.
- **Refuse to run any show once a pack fails.** Honest but worse: a user with three built-in
  characters and one broken download would lose the app over it. Falling forward to another *real*
  character keeps a working app; what must never happen is the fall being silent.
- **Keep the placeholder listed as "Placeholder".** It is stand-in art from before there was any,
  and offering it as a choice invites exactly the confusion this decision removes.

## Consequences

- `PackLibrary.current` is optional: `nil` means the app is wearing nothing, which is a state the
  UI and the summon path have to answer for rather than paper over.
- A pack whose *manifest leaves a role out* still borrows the placeholder's sheet or sound for that
  role. That is the documented pack format (`docs/adr/0003-character-packs.md`), not a failure: a
  `pack.json` alone is a valid re-skin. The rule here is about a pack that cannot be loaded at all.
- Anyone whose saved choice was the placeholder is moved to the first-run character on the next
  launch, because their saved id no longer names anything.

- A saved selection whose folder or manifest is missing/unreadable follows the same load-failure
  path as unreadable artwork. Discovery cannot silently replace it before reporting. A refresh
  retains the previously known name; a missing saved folder at launch is named from its saved id.
  The report is delivered after a real replacement settles, or names the still-loaded character
  if every replacement fails. User-facing recovery is translated by `CharacterFailure`; raw
  manifest, image and archive diagnostics remain in developer logs.
- Unreadable first-run Kaiju information follows that same failure path even when discovery
  cannot list it. A saved choice still wins. The loaded entry owns the working character's name;
  scanning a replacement folder cannot rename artwork retained after a failed reinstall.
- Installation failures name the working character after the entire dropped batch settles, or
  say none is available. A later successful installation in that batch therefore supplies the
  replacement name in earlier failure messages.
