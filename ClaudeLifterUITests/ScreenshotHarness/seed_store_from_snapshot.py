#!/usr/bin/env python3
"""Seed the simulator app's SwiftData store from a cloud-mirror snapshot.

Screenshot harness only. Why this exists: Settings → Restore from Cloud is
the app's own path for this, but on the iOS 26.5 simulator no Form row button
in Settings responds to a tap (Restore, Export, Import). `SettingsView` puts
`.onTapGesture { focusedField = nil }` on the whole Form, which appears to
swallow the row-selection tap those buttons rely on. So the harness writes the
same records the restore would, straight into the store, with the app closed.

Usage (app must NOT be running; the store must already exist, i.e. the app
has launched once and imported the bundled exercise catalog):

    python3 -I seed_store_from_snapshot.py --store <.../default.store> \
        --snapshot snapshot.json

What it writes: completed workouts (in-progress drafts are skipped), templates,
the one custom exercise, body-weight entries, exercise reports, and the
bundled-exercise notes overlays. Exercise references resolve by exact name
against the bundled catalog (the restore's own fallback rule). Everything is
marked `synced` so nothing is pushed. Re-running wipes and re-seeds those
tables. Schema assumptions: SwiftData V4 (entity order in Z_PRIMARYKEY).
"""

import argparse
import json
import sqlite3
import sys
import uuid
from datetime import datetime

EPOCH_2001 = 978307200.0


def ts(iso):
    if not iso:
        return None
    return datetime.fromisoformat(iso.replace("Z", "+00:00")).timestamp() - EPOCH_2001


def uid(value):
    return uuid.UUID(value).bytes if value else None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--store", required=True)
    parser.add_argument("--snapshot", required=True)
    args = parser.parse_args()

    snap = json.load(open(args.snapshot))["snapshot"]
    db = sqlite3.connect(args.store)
    ent = {name: num for num, name in db.execute("SELECT Z_ENT, Z_NAME FROM Z_PRIMARYKEY")}
    needed = ["Workout", "WorkoutExercise", "WorkoutSet", "WorkoutTemplate",
              "TemplateExercise", "BodyWeightEntry", "ExerciseReport", "Exercise"]
    missing = [n for n in needed if n not in ent]
    if missing:
        sys.exit("store schema lacks entities: %s" % missing)

    # Column names for the inverse foreign keys carry the parent's entity number.
    we_parent = "Z%dEXERCISES" % ent["Workout"]
    set_parent = "Z%dSETS" % ent["WorkoutExercise"]
    te_parent = "Z%dEXERCISES" % ent["WorkoutTemplate"]
    for table, col in [("ZWORKOUTEXERCISE", we_parent), ("ZWORKOUTSET", set_parent),
                       ("ZTEMPLATEEXERCISE", te_parent)]:
        cols = [c[1] for c in db.execute("PRAGMA table_info(%s)" % table)]
        if col not in cols:
            sys.exit("%s has no %s column: schema changed" % (table, col))

    for table in ["ZWORKOUTSET", "ZWORKOUTEXERCISE", "ZWORKOUT", "ZTEMPLATEEXERCISE",
                  "ZWORKOUTTEMPLATE", "ZBODYWEIGHTENTRY", "ZEXERCISEREPORT"]:
        db.execute("DELETE FROM %s" % table)
    db.execute("DELETE FROM ZEXERCISE WHERE ZISCUSTOM = 1")

    def next_pk(table):
        return (db.execute("SELECT COALESCE(MAX(Z_PK), 0) FROM %s" % table).fetchone()[0]) + 1

    by_name = {name: pk for pk, name in db.execute("SELECT Z_PK, ZNAME FROM ZEXERCISE")}
    by_ext = {ext: pk for pk, ext in db.execute(
        "SELECT Z_PK, ZEXTERNALID FROM ZEXERCISE WHERE ZEXTERNALID IS NOT NULL")}

    # Custom exercises: borrow array blobs (NSKeyedArchiver plists) from a
    # bundled row so the encoding is exactly what SwiftData wrote itself.
    template_row = db.execute(
        "SELECT ZINSTRUCTIONS, ZPRIMARYMUSCLES, ZSECONDARYMUSCLES FROM ZEXERCISE "
        "WHERE ZNAME = 'Leg Press'").fetchone()
    pk = next_pk("ZEXERCISE")
    for ex in snap.get("customExercises", []):
        db.execute(
            "INSERT INTO ZEXERCISE (Z_PK, Z_ENT, Z_OPT, ZISCUSTOM, ZEQUIPMENT, ZEXTERNALID, "
            "ZNAME, ZNOTES, ZID, ZINSTRUCTIONS, ZPRIMARYMUSCLES, ZSECONDARYMUSCLES, ZMECHANIC) "
            "VALUES (?,?,1,1,?,?,?,?,?,?,?,?,?)",
            (pk, ent["Exercise"], ex.get("equipment"), ex.get("externalId"), ex["name"],
             ex.get("notes"), uid(ex["id"]),
             template_row[0] if template_row else None,
             template_row[1] if template_row else None,
             template_row[2] if template_row else None,
             ex.get("mechanic")))
        by_name[ex["name"]] = pk
        pk += 1

    for overlay in snap.get("exerciseOverlays", []):
        ext = overlay.get("externalId") or overlay.get("id")
        if ext in by_ext:
            db.execute("UPDATE ZEXERCISE SET ZNOTES = ? WHERE Z_PK = ?",
                       (overlay.get("notes"), by_ext[ext]))

    unresolved = set()

    def exercise_pk(name):
        if name in by_name:
            return by_name[name]
        unresolved.add(name)
        return None

    t_pk, te_pk = next_pk("ZWORKOUTTEMPLATE"), next_pk("ZTEMPLATEEXERCISE")
    for t in snap.get("templates", []):
        db.execute(
            "INSERT INTO ZWORKOUTTEMPLATE (Z_PK, Z_ENT, Z_OPT, ZTIMESPERFORMED, ZCREATEDAT, "
            "ZLASTMODIFIED, ZLASTPERFORMEDAT, ZUPDATEDAT, ZNAME, ZNOTES, ZSYNCSTATUSRAW, ZID) "
            "VALUES (?,?,1,?,?,?,?,?,?,?,'synced',?)",
            (t_pk, ent["WorkoutTemplate"], t.get("timesPerformed", 0), ts(t.get("createdAt")),
             ts(t.get("lastModified")), ts(t.get("lastPerformedAt")), ts(t.get("updatedAt")),
             t["name"], t.get("notes"), uid(t["id"])))
        for e in t.get("exercises", []):
            db.execute(
                "INSERT INTO ZTEMPLATEEXERCISE (Z_PK, Z_ENT, Z_OPT, ZDEFAULTREPS, "
                "ZDEFAULTRESTSECONDS, ZDEFAULTSETS, ZORDER, ZEXERCISE, %s, ZDEFAULTWEIGHT, "
                "ZNOTES, ZID) VALUES (?,?,1,?,?,?,?,?,?,?,?,?)" % te_parent,
                (te_pk, ent["TemplateExercise"], e.get("defaultReps", 10),
                 e.get("defaultRestSeconds", 90), e.get("defaultSets", 3), e["order"],
                 exercise_pk(e.get("exerciseName")), t_pk, e.get("defaultWeight"),
                 e.get("notes"), uid(e["id"])))
            te_pk += 1
        t_pk += 1

    w_pk, we_pk, s_pk = next_pk("ZWORKOUT"), next_pk("ZWORKOUTEXERCISE"), next_pk("ZWORKOUTSET")
    for w in snap.get("workouts", []):
        if not w.get("completedAt"):
            continue
        db.execute(
            "INSERT INTO ZWORKOUT (Z_PK, Z_ENT, Z_OPT, ZCOMPLETEDAT, ZLASTMODIFIED, ZSTARTEDAT, "
            "ZNAME, ZNOTES, ZSYNCSTATUSRAW, ZID, ZTEMPLATEID) VALUES (?,?,1,?,?,?,?,?,'synced',?,?)",
            (w_pk, ent["Workout"], ts(w["completedAt"]), ts(w.get("lastModified")),
             ts(w["startedAt"]), w["name"], w.get("notes"), uid(w["id"]),
             uid(w.get("templateId"))))
        for e in w.get("exercises", []):
            db.execute(
                "INSERT INTO ZWORKOUTEXERCISE (Z_PK, Z_ENT, Z_OPT, ZORDER, ZRESTSECONDS, "
                "ZEXERCISE, %s, ZNOTES, ZID) VALUES (?,?,1,?,?,?,?,?,?)" % we_parent,
                (we_pk, ent["WorkoutExercise"], e["order"], e.get("restSeconds", 90),
                 exercise_pk(e.get("exerciseName")), w_pk, e.get("notes"), uid(e["id"])))
            for s in e.get("sets", []):
                db.execute(
                    "INSERT INTO ZWORKOUTSET (Z_PK, Z_ENT, Z_OPT, ZISCOMPLETED, ZORDER, ZREPS, "
                    "%s, ZCOMPLETEDAT, ZWEIGHT, ZNOTES, ZWEIGHTUNIT, ZID) "
                    "VALUES (?,?,1,?,?,?,?,?,?,?,?,?)" % set_parent,
                    (s_pk, ent["WorkoutSet"], 1 if s.get("isCompleted") else 0, s["order"],
                     s.get("reps"), we_pk, ts(s.get("completedAt")), s.get("weight"),
                     s.get("notes"), s.get("weightUnit", "kg"), uid(s["id"])))
                s_pk += 1
            we_pk += 1
        w_pk += 1

    b_pk = next_pk("ZBODYWEIGHTENTRY")
    for b in snap.get("bodyWeightEntries", []):
        db.execute(
            "INSERT INTO ZBODYWEIGHTENTRY (Z_PK, Z_ENT, Z_OPT, ZLASTMODIFIED, ZRECORDEDAT, "
            "ZWEIGHTKG, ZSOURCE, ZSYNCSTATUSRAW, ZHEALTHKITSAMPLEUUID, ZID) "
            "VALUES (?,?,1,?,?,?,?,'synced',?,?)",
            (b_pk, ent["BodyWeightEntry"], ts(b.get("lastModified")), ts(b["recordedAt"]),
             b["weightKg"], b.get("source", "manual"), uid(b.get("healthKitSampleUUID")),
             uid(b["id"])))
        b_pk += 1

    r_pk = next_pk("ZEXERCISEREPORT")
    for r in snap.get("exerciseReports", []):
        db.execute(
            "INSERT INTO ZEXERCISEREPORT (Z_PK, Z_ENT, Z_OPT, ZCREATEDAT, ZLASTMODIFIED, "
            "ZAPPVERSION, ZCATEGORYRAW, ZCONTEXTSUMMARY, ZDETAIL, ZEXERCISEEXTERNALID, "
            "ZEXERCISENAME, ZIOSVERSION, ZPHOTOURL, ZRESOLUTION, ZSTATUSRAW, "
            "ZSUGGESTEDREPLACEMENT, ZSYNCSTATUSRAW, ZID, ZTEMPLATEID, ZWORKOUTEXERCISEID, "
            "ZWORKOUTID) VALUES (?,?,1,?,?,?,?,?,?,?,?,?,?,?,?,?,'synced',?,?,?,?)",
            (r_pk, ent["ExerciseReport"], ts(r["createdAt"]), ts(r.get("lastModified")),
             r.get("appVersion"), r.get("category", "other"), r.get("contextSummary"),
             r.get("detail", ""), r.get("exerciseExternalId"), r.get("exerciseName"),
             r.get("iosVersion"), r.get("photoURL"), r.get("resolution"),
             r.get("status", "open"), r.get("suggestedReplacement"), uid(r["id"]),
             uid(r.get("templateId")), uid(r.get("workoutExerciseId")),
             uid(r.get("workoutId"))))
        r_pk += 1

    for name, table in [("Workout", "ZWORKOUT"), ("WorkoutExercise", "ZWORKOUTEXERCISE"),
                        ("WorkoutSet", "ZWORKOUTSET"), ("WorkoutTemplate", "ZWORKOUTTEMPLATE"),
                        ("TemplateExercise", "ZTEMPLATEEXERCISE"),
                        ("BodyWeightEntry", "ZBODYWEIGHTENTRY"),
                        ("ExerciseReport", "ZEXERCISEREPORT"), ("Exercise", "ZEXERCISE")]:
        db.execute("UPDATE Z_PRIMARYKEY SET Z_MAX = (SELECT COALESCE(MAX(Z_PK),0) FROM %s) "
                   "WHERE Z_NAME = ?" % table, (name,))
    db.commit()
    db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    counts = {t: db.execute("SELECT count(*) FROM %s" % t).fetchone()[0]
              for t in ["ZWORKOUT", "ZWORKOUTSET", "ZWORKOUTTEMPLATE", "ZBODYWEIGHTENTRY",
                        "ZEXERCISEREPORT"]}
    print("seeded", counts)
    if unresolved:
        print("UNRESOLVED exercise names (left without an exercise):", sorted(unresolved))
    db.close()


if __name__ == "__main__":
    main()
