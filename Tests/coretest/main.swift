import Foundation

let fm = FileManager.default
let root = URL(fileURLWithPath: NSTemporaryDirectory() + "BPMCoreTest-\(UUID().uuidString)")
try fm.createDirectory(at: root, withIntermediateDirectories: true)

func touch(_ rel: String) {
    let url = root.appendingPathComponent(rel)
    try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    fm.createFile(atPath: url.path, contents: Data("x".utf8))
}
func exists(_ rel: String) -> Bool {
    fm.fileExists(atPath: root.appendingPathComponent(rel).path)
}

// 根目录：A 有 JPG 匹配，B 无匹配，C 大小写不同也算匹配
touch("IMG_A.CR3"); touch("IMG_A.JPG")
touch("IMG_B.CR3")
touch("img_c.cr3"); touch("IMG_C.jpg")
// 子目录：D 无匹配
touch("sub/IMG_D.NEF")
// 一个 JPG 单独存在
touch("sub/SOLO.JPG")

let mgr = PhotoManager()
mgr.setRoot(root)

func check(_ cond: Bool, _ msg: String) {
    print("\(cond ? "PASS" : "FAIL"): \(msg)")
    if !cond { exit(1) }
}

check(mgr.stats.dirCount == 2, "扫描到 2 个文件夹（根目录 + sub），实际 \(mgr.stats.dirCount)")
check(mgr.stats.rawCount == 4, "RAW 共 4 个，实际 \(mgr.stats.rawCount)")
check(mgr.stats.jpgCount == 3, "JPG 共 3 个，实际 \(mgr.stats.jpgCount)")
check(mgr.stats.matchedRawCount == 2, "匹配 RAW 共 2 个（A、C），实际 \(mgr.stats.matchedRawCount)")
check(mgr.stats.unmatchedRawCount == 2, "无匹配 RAW 共 2 个（B、D），实际 \(mgr.stats.unmatchedRawCount)")

// 任务1：移出无匹配 RAW
let plan1 = mgr.preview(for: .unmatchedRaw)
check(plan1.count == 2, "任务1 预览 2 个文件，实际 \(plan1.count)")
let r1 = mgr.run(.unmatchedRaw)
check(r1.succeeded == 2 && r1.failed == 0, "任务1 移动成功 2 个，实际 \(r1.succeeded)/\(r1.failed)")
check(exists("无同名JPG的RAW/IMG_B.CR3"), "IMG_B.CR3 移入根目录的无匹配目录")
check(exists("sub/无同名JPG的RAW/IMG_D.NEF"), "IMG_D.NEF 移入 sub 的无匹配目录")
check(!exists("IMG_B.CR3") && !exists("sub/IMG_D.NEF"), "源文件已移走")

// 撤销
let u1 = mgr.undoLast()
check(u1.restored == 4 && u1.failed == 0, "撤销恢复 4 项（2 移动 + 2 空目录），实际 \(u1.restored)/\(u1.failed)")
check(exists("IMG_B.CR3"), "IMG_B.CR3 撤销后回到根目录")
check(exists("sub/IMG_D.NEF"), "IMG_D.NEF 撤销后回到 sub")

// 任务3：有同名 JPG 的 RAW（范围开关默认开 = 含子文件夹）
check(mgr.includeSubfolders, "范围开关默认包括子文件夹")
let plan3 = mgr.preview(for: .matchedRaw)
check(plan3.count == 2, "任务3 匹配 RAW 2 个（A、C，大小写不敏感），实际 \(plan3.count)")
let r3 = mgr.run(.matchedRaw)
check(r3.succeeded == 2, "任务3 成功 2 个，实际 \(r3.succeeded)")
check(exists("所有目录同名JPG的RAW/IMG_A.CR3"), "IMG_A.CR3 进入匹配目录")
check(exists("所有目录同名JPG的RAW/img_c.cr3"), "img_c.cr3 进入匹配目录")

// 任务2：汇总全部 RAW（复制）—— 2 个匹配 RAW 已进入生成目录，会被跳过，剩 IMG_B + IMG_D
let plan2 = mgr.preview(for: .allRaw)
check(plan2.count == 2, "任务2 复制全部 RAW 2 个（跳过生成目录），实际 \(plan2.count)")
let r2 = mgr.run(.allRaw)
check(r2.succeeded == 2, "任务2 复制成功 2 个，实际 \(r2.succeeded)")
check(exists("IMG_B.CR3"), "复制模式下原文件仍保留")
check(exists("全部RAW/IMG_B.CR3"), "复制产物进入全部RAW目录")

// ============ 范围开关测试（独立干净目录）============
let suuid = UUID().uuidString.prefix(8)
let rootS = URL(fileURLWithPath: NSTemporaryDirectory() + "BPMScopeTest-\(suuid)")
try fm.createDirectory(at: rootS, withIntermediateDirectories: true)
func touchS(_ rel: String) {
    let url = rootS.appendingPathComponent(rel)
    try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    fm.createFile(atPath: url.path, contents: Data("z".utf8))
}
func existsS(_ rel: String) -> Bool { fm.fileExists(atPath: rootS.appendingPathComponent(rel).path) }

// 根目录 1 个无匹配 RAW，子目录 1 个无匹配 RAW / 1 个落单 JPG
touchS("ROOT_RAW.CR3")
touchS("sub/SUB_RAW.CR3")
touchS("sub/SUB_SOLO.JPG")

let mgrS = PhotoManager()
mgrS.setRoot(rootS)

// 默认含子文件夹：3 个任务都应看到子目录里的文件
check(mgrS.preview(for: .unmatchedRaw).count == 2, "含子文件夹：无匹配 RAW 2 个（ROOT+SUB）")
check(mgrS.preview(for: .deleteOrphanJpg).count == 1, "含子文件夹：落单 JPG 1 个（SUB_SOLO）")
check(mgrS.stats.dirCount == 2 && mgrS.stats.rawCount == 2 && mgrS.stats.jpgCount == 1,
      "含子文件夹统计：2 目录 / 2 RAW / 1 JPG，实际 \(mgrS.stats.dirCount)/\(mgrS.stats.rawCount)/\(mgrS.stats.jpgCount)")

// 关闭范围：只看根目录（统计须随勾选框即时重算）
mgrS.includeSubfolders = false
check(mgrS.preview(for: .unmatchedRaw).count == 1, "仅当前文件夹：无匹配 RAW 1 个（仅 ROOT）")
check(mgrS.preview(for: .deleteOrphanJpg).count == 0, "仅当前文件夹：落单 JPG 0 个（子目录被排除）")
check(mgrS.targetURL(for: .matchedRaw)?.lastPathComponent == "当前目录同名JPG的RAW", "仅当前文件夹：目标目录名为当前目录版")
check(mgrS.stats.dirCount == 1 && mgrS.stats.rawCount == 1 && mgrS.stats.jpgCount == 0 && mgrS.stats.orphanJpgCount == 0,
      "关闭范围后统计重算：1 目录 / 1 RAW / 0 JPG，实际 \(mgrS.stats.dirCount)/\(mgrS.stats.rawCount)/\(mgrS.stats.jpgCount)")

mgrS.includeSubfolders = true
check(mgrS.targetURL(for: .matchedRaw)?.lastPathComponent == "所有目录同名JPG的RAW", "含子文件夹：目标目录名为所有目录版")
check(mgrS.stats.dirCount == 2 && mgrS.stats.rawCount == 2 && mgrS.stats.jpgCount == 1,
      "重新勾选后统计恢复：2 目录 / 2 RAW / 1 JPG，实际 \(mgrS.stats.dirCount)/\(mgrS.stats.rawCount)/\(mgrS.stats.jpgCount)")
try? fm.removeItem(at: rootS)

// ============ 删除任务测试（独立干净目录）============
let uuid = UUID().uuidString.prefix(8)
let root2 = URL(fileURLWithPath: NSTemporaryDirectory() + "BPMTrashTest-\(uuid)")
try fm.createDirectory(at: root2, withIntermediateDirectories: true)
func touch2(_ rel: String) {
    let url = root2.appendingPathComponent(rel)
    try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    fm.createFile(atPath: url.path, contents: Data("y".utf8))
}
func exists2(_ rel: String) -> Bool { fm.fileExists(atPath: root2.appendingPathComponent(rel).path) }

// 根目录：DEL_A 有 RAW+JPG（保留）；DEL_B 只有 RAW（应删）；DEL_SOLO 只有 JPG（应删）
touch2("DEL_A.CR3"); touch2("DEL_A.JPG")
touch2("DEL_B.CR3")
touch2("sub/DEL_SOLO.JPG")

let mgr2 = PhotoManager()
mgr2.setRoot(root2)
check(mgr2.stats.orphanJpgCount == 1, "无同名 RAW 的 JPG 1 个（DEL_SOLO），实际 \(mgr2.stats.orphanJpgCount)")

// 删除无同名 JPG 的 RAW
let pDelRaw = mgr2.preview(for: .deleteUnmatchedRaw)
check(pDelRaw.count == 1, "删除任务预览 1 个 RAW（DEL_B），实际 \(pDelRaw.count)")
let rDelRaw = mgr2.run(.deleteUnmatchedRaw)
check(rDelRaw.succeeded == 1 && rDelRaw.isTrash, "删除 RAW 成功 1 个且标记为废纸篓，实际 \(rDelRaw.succeeded)")
check(!exists2("DEL_B.CR3"), "DEL_B.CR3 已从原位置消失（进了废纸篓）")
check(exists2("DEL_A.CR3"), "有匹配的 DEL_A.CR3 未被删除")

// 撤销删除：从废纸篓搬回
let uDel = mgr2.undoLast()
check(uDel.trashedRestored == 1 && uDel.failed == 0, "撤销从废纸篓搬回 1 个，实际 \(uDel.trashedRestored)/\(uDel.failed)")
check(exists2("DEL_B.CR3"), "DEL_B.CR3 撤销后回到原位置")

// 删除无同名 RAW 的 JPG
let pDelJpg = mgr2.preview(for: .deleteOrphanJpg)
check(pDelJpg.count == 1, "删除任务预览 1 个 JPG（DEL_SOLO），实际 \(pDelJpg.count)")
let rDelJpg = mgr2.run(.deleteOrphanJpg)
check(rDelJpg.succeeded == 1, "删除 JPG 成功 1 个，实际 \(rDelJpg.succeeded)")
check(!exists2("sub/DEL_SOLO.JPG"), "DEL_SOLO.JPG 已从原位置消失")
let uDel2 = mgr2.undoLast()
check(uDel2.trashedRestored == 1 && exists2("sub/DEL_SOLO.JPG"), "撤销后 DEL_SOLO.JPG 回到 sub")

print("ALL DONE. root=\(root.path) root2=\(root2.path)")
try? fm.removeItem(at: root)
try? fm.removeItem(at: root2)
