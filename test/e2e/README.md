# The real-system end-to-end suite

Roadmap lane H (H2, H3, H4). Everything in this directory runs against a real
Go service on a real PostgreSQL, over real HTTP, through the app's real
`HttpSyncTransport` and real repositories. The in-process fake in
`test/sync/support/fake_server.dart` is what this lane replaces: a fake and its
client can agree with each other and both be wrong about the contract.

## Running it

```bash
bash tool/e2e/run.sh
```

The script is the harness, and it does the whole thing:

1. starts `postgres:17-alpine` in Docker on a free port and waits for it;
2. builds `scrollaryd` from the service repository and starts it on a free
   port against that database, in development mode;
3. samples every TCP socket the service holds, every 0.2s, for the whole run;
4. runs `flutter test test/e2e` with `--dart-define=SCROLLARY_E2E_BASE_URL`;
5. asserts the service's only TCP peers were the postgres container and the
   test client, and that the simulated source sites were never fetched;
6. kills the service, starts it again on the same database, and re-runs the
   `restart_persistence` group across the restart;
7. tears down the container and the process, on success or failure.

The service repository is found through `SCROLLARY_BACKEND_DIR`, or beside the
app repository as `../scrollary-backend`.

Without the define every file skips itself with a message, so
`flutter test` stays network-free and needs no backend:

```
$ flutter test test/e2e
00:01 +0 ~7: All tests skipped.
```

## What each file covers

| File | Scenario |
|---|---|
| `h2_client_to_phone_test.dart` | H2 — a local library is built, drained, and read back off the wire as the contract's rows; a second phone bootstraps from cursor 0 and matches |
| `h3_offline_reconnect_test.dart` | H3 — an offline mutation is durable and drains on reconnect; a replayed batch is a duplicate; an interrupted pull resumes per committed page; reading state inverts on the reading clock |
| `identity_and_removal_test.dart` | Provisional identity meets canonical identity through `POST /identity/arbitrate`; a removal from another device leaves this device's bytes (I14) |
| `h4_download_to_mobile_test.dart` | H4 — an extension records an intent, a phone claims it, the save waits for Start, a racing phone loses, outcomes are reported; the source sites count zero requests |
| `multi_source_test.dart` | Two Sources of one Collection, one Entry, scoped measurements, a dead Source, the renumbering conflict, and central placement arbitration |
| `standalone_and_folder_test.dart` | A standalone Entry is never wrapped in a Collection; deleting a Folder reparents its children and has to converge |
| `restart_persistence_test.dart` | The feed, the revision counter and the mutation ledger survive the service being killed |

## House rules for this directory

- **Every test uses its own development library.** `uniqueLibrary()` mints an
  `X-Scrollary-Library` value per test, so runs are independent of each other
  and of whatever is already in the database.
- **No sleeps.** The harness polls with deadlines; the tests await real
  replies.
- **Reserved example hosts only.** Addresses come from the in-process fixture
  site on loopback, which is also what makes "nobody fetched anything"
  measurable.
- **The restart file is inert without its phase defines**, and its verify
  phase is single-shot: it mutates the library it verified, so re-running it
  against the same handoff will not agree with itself.

## What the run currently reports

Two tests fail, and both are failing about the product rather than about
themselves. They are written to assert what the design says should happen, and
left failing on purpose — the run is the report.

- **`standalone_and_folder_test.dart`: deleting a Folder reparents its children
  and converges.** The service reparents (the raw assertions above the failure
  pass), but the reparented rows keep the revision they already had, so the
  change feed never re-announces them. The second client receives only the
  tombstone and its `DELETE FROM folders` is refused by the RESTRICT foreign
  key that exists to stop content being lost:
  `SqliteException(1811): FOREIGN KEY constraint failed`. That client never
  converges.
- **`h3_offline_reconnect_test.dart`: a client bootstrapping after a parent was
  renamed receives its children.** The feed carries each row once, at the
  revision it currently holds, so a renamed Collection sorts *behind* its own
  Sources, Entries and Locations. A client bootstrapping from cursor 0 meets
  the children first, skips them (their parent is not local yet) and commits
  the cursor past them in the same transaction, so they are never offered
  again. Measured: 2 of 7 changes applied.
