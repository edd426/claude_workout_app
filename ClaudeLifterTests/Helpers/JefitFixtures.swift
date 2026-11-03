import Foundation

/// A small, entirely invented Jefit export (#166). It mimics the real file's
/// shape — `### NAME ###` sections, quoted `logs` strings, epoch-second
/// session times — and nothing in it comes from a real export.
///
/// What it exercises:
/// - S1, S2 (March 2024) are logged in **pounds**; S4, S5 (July 2025) in
///   **kilograms**. EXERCISE SET LOGS confirm both sides (ratio 1 and 2.20462).
/// - S3 has no exercise logs (skipped as empty).
/// - Log 7 is a malformed row (wrong column count).
/// - Log 5 has one malformed set part (`abcx5`).
/// - Log 6 is a timed plank padded with `0x0` sets.
/// - Log 12 belongs to a session that is not in WORKOUT SESSIONS (orphan).
/// - "Zorbo Press" is a Jefit custom exercise no table or catalog knows.
/// - "Push Up" is bodyweight (`0xN`); "Crunch" carries Jefit's constant 10
///   placeholder weight on every set.
/// - S4 has no end time, only `total_time`.
/// - CARDIO LOGS, PROFILE, ROUTINES, NOTES (with a multi-line quoted note),
///   EXERCISE RECORDS and an empty FAVORITE EXERCISES are present and skipped.
enum JefitFixtures {
    static let s1Start: TimeInterval = 1_709_546_400   // 2024-03-04T10:00:00Z
    static let s2Start: TimeInterval = 1_710_151_200   // 2024-03-11T10:00:00Z
    static let s4Start: TimeInterval = 1_751_356_800   // 2025-07-01T08:00:00Z
    static let s5Start: TimeInterval = 1_751_961_600   // 2025-07-08T08:00:00Z
    static let orphanLogTime: TimeInterval = 1_752_566_400 // 2025-07-15T08:00:00Z

    static let export = """

    ### SETTING ##########################################

    row_id,USERID,TIMESTAMP,mass,length
    1,1,2025-01-01 00:00:00,kg,cm

    ######################################################

    ### PROFILE ##########################################

    row_id,USERID,TIMESTAMP,_id,mydate,weight,waist
    1,1,2024-01-01 00:00:00,1,2024-01-01,150,30

    ######################################################

    ### ROUTINES #########################################

    row_id,USERID,TIMESTAMP,_id,name
    1,1,2024-01-01 00:00:00,1,"Push, Pull, Legs"

    ######################################################

    ### WORKOUT SESSIONS #################################

    rowid,_id,USERID,edit_time,day_id,total_time,starttime,endtime
    1,1001,1,0,1,3600,1709546400,1709550000
    2,1002,1,0,2,3600,1710151200,1710154800
    3,1003,1,0,3,3600,1710756000,1710759600
    4,1004,1,0,4,2700,1751356800,0
    5,1005,1,0,5,3600,1751961600,1751965200

    ######################################################

    ### EXERCISE LOGS ####################################

    USERID,TIMESTAMP,belongSys,logs,_id,record,mydate,eid,ename,day_item_id,belongsession,logTime,interval_logs,auto_generated
    1,2024-03-04 11:00:00,1,"225x5,235x5",1,0,2024-03-04,9,Barbell Squat,1,1001,1709548200,"0,0",
    1,2024-03-04 11:00:00,1,"180x10,180x10",2,0,2024-03-04,11,Machine Single-Leg Press,2,1001,1709549000,"0,0",
    1,2024-03-04 11:00:00,1,"0x15,0x12",3,0,2024-03-04,12,Push Up,3,1001,1709549500,"0,0",
    1,2024-03-11 11:00:00,1,"230x5,240x5,245x3",4,0,2024-03-11,9,Barbell Squat,1,1002,1710153000,"0,0,0",
    1,2024-03-11 11:00:00,0,"50x8,abcx5,55x8",5,0,2024-03-11,1,Zorbo Press,4,1002,1710153600,"0,0,0",
    1,2024-03-11 11:00:00,1,"0x45,0x0,0x0",6,0,2024-03-11,13,Plank,5,1002,1710154000,"0,0,0",
    1,broken row
    1,2025-07-01 09:00:00,1,"100x5,102.5x5",8,0,2025-07-01,9,Barbell Squat,1,1004,0,"0,0",
    1,2025-07-01 09:00:00,0,25x8,9,0,2025-07-01,1,Zorbo Press,4,1004,1751358600,0,
    1,2025-07-08 09:00:00,1,"59.9998x8,105x3",10,0,2025-07-08,9,Barbell Squat,1,1005,1751963400,"0,0",
    1,2025-07-08 09:00:00,1,80x10,11,0,2025-07-08,11,Machine Single-Leg Press,2,1005,1751964000,0,
    1,2025-07-15 09:00:00,1,100x5,12,0,2025-07-15,9,Barbell Squat,1,9999,1752566400,0,
    1,2024-03-04 11:00:00,1,"10x20,10x20,10x20",13,0,2024-03-04,14,Crunch,6,1001,1709549800,"0,0,0",
    1,2024-03-11 11:00:00,1,"10x20,10x20",14,0,2024-03-11,14,Crunch,6,1002,1710154200,"0,0",

    ######################################################

    ### EXERCISE SET LOGS ################################

    _id,userid,exercise_log_id,set_index,weight_lbs,reps,calories,distance_mi,speed_mph,laps,duration,set_type,log_time,TIMESTAMP
    1,1,4,0,230,5,0,0,0,0,0,default,1710153000,2024-03-11 11:00:00
    2,1,8,0,220.462,5,0,0,0,0,0,default,1751358000,2025-07-01 09:00:00
    3,1,8,1,225.974,5,0,0,0,0,0,default,1751358100,2025-07-01 09:00:00

    ######################################################

    ### EXERCISE RECORDS #################################

    row_id,USERID,TIMESTAMP,_id,belongSys,record,eid,target1RM,mydate
    1,1,2024-03-11 11:00:00,1,1,287,9,0,2024-03-11

    ######################################################

    ### CARDIO LOGS ######################################

    row_id,TIMESTAMP,USERID,_id,weeklyLogId,eid,belongSys,lap,duration,speed,distance,calorie,mydate
    1,2024-03-04 11:00:00,1,1,0,500,1,0,1200,6,2,200,2024-03-04

    ######################################################

    ### CUSTOM EXERCISES #################################

    row_id,USERID,TIMESTAMP,rating,name,description,image2,image1,bodypart,bodypart3,bodypart2,_id,equip1,equip2,recordtype,link,hashcode,unilateral,sys_exercise_map_id
    1,1,2024-01-01 00:00:00,0,Zorbo Press,"An invented press, for tests",,,0,0,0,1,0,0,0,,,0,

    ######################################################

    ### FAVORITE EXERCISES ###############################

    ######################################################

    ### NOTES ############################################

    row_id,TIMESTAMP,USERID,_id,eid,belongSys,mynote,title,mydate
    1,2024-03-04 11:00:00,1,1,9,1,"Felt strong.
    Second line, with a comma",Squat note,2024-03-04

    ######################################################

    """
}
