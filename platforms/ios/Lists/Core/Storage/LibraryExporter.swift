import Foundation

public enum LibraryExporter {
    public static func exportLibrary(
        at root: URL,
        now: Date = .now,
        fileManager: FileManager = .default
    ) throws -> URL {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let exportDir = fileManager.temporaryDirectory
            .appendingPathComponent("ListsExports", isDirectory: true)
        try fileManager.createDirectory(at: exportDir, withIntermediateDirectories: true)
        removeOldExports(in: exportDir, olderThan: now.addingTimeInterval(-86_400), fileManager: fileManager)

        let fileName = "Lists-\(timestamp(for: now))-\(UUID().uuidString.prefix(8)).zip"
        let destination = exportDir.appendingPathComponent(fileName)
        try ZipArchiveWriter.writeArchive(
            sourceRoot: root,
            archiveRootName: "Lists",
            to: destination,
            now: now,
            fileManager: fileManager
        )
        return destination
    }

    private static func removeOldExports(
        in directory: URL,
        olderThan cutoff: Date,
        fileManager: FileManager
    ) {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        for url in urls
        where url.pathExtension == "zip" && url.lastPathComponent.hasPrefix("Lists-") {
            guard let modifiedAt = try? url.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate,
                  modifiedAt < cutoff else { continue }
            try? fileManager.removeItem(at: url)
        }
    }

    private static func timestamp(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}

private enum ZipArchiveWriter {
    private struct SourceEntry {
        let archivePath: String
        let url: URL?
        let isDirectory: Bool
        let modifiedAt: Date
    }

    private struct WrittenEntry {
        let source: SourceEntry
        let crc32: UInt32
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let localHeaderOffset: UInt32
        let dosTime: UInt16
        let dosDate: UInt16
    }

    static func writeArchive(
        sourceRoot: URL,
        archiveRootName: String,
        to destination: URL,
        now: Date,
        fileManager: FileManager
    ) throws {
        let entries = try sourceEntries(
            under: sourceRoot,
            archiveRootName: archiveRootName,
            now: now,
            fileManager: fileManager
        )

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        _ = fileManager.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }

        var offset: UInt64 = 0
        var written: [WrittenEntry] = []
        for entry in entries {
            let fileData = entry.url.map { try? Data(contentsOf: $0) } ?? Data()
            guard let data = fileData else {
                throw ZipArchiveError.couldNotRead(entry.archivePath)
            }

            let fileName = try utf8Bytes(entry.archivePath)
            let (dosTime, dosDate) = dosTimestamp(for: entry.modifiedAt)
            let crc = entry.isDirectory ? 0 : CRC32.checksum(data)
            let size = try checkedUInt32(UInt64(data.count), "file size for \(entry.archivePath)")
            let localOffset = try checkedUInt32(offset, "local header offset for \(entry.archivePath)")

            var localHeader = Data()
            localHeader.appendUInt32LE(0x0403_4B50)
            localHeader.appendUInt16LE(20)
            localHeader.appendUInt16LE(0x0800)
            localHeader.appendUInt16LE(0)
            localHeader.appendUInt16LE(dosTime)
            localHeader.appendUInt16LE(dosDate)
            localHeader.appendUInt32LE(crc)
            localHeader.appendUInt32LE(size)
            localHeader.appendUInt32LE(size)
            localHeader.appendUInt16LE(try checkedUInt16(UInt64(fileName.count), "file name length"))
            localHeader.appendUInt16LE(0)
            localHeader.append(fileName)

            try handle.write(contentsOf: localHeader)
            offset += UInt64(localHeader.count)
            if !entry.isDirectory {
                try handle.write(contentsOf: data)
                offset += UInt64(data.count)
            }

            written.append(WrittenEntry(
                source: entry,
                crc32: crc,
                compressedSize: size,
                uncompressedSize: size,
                localHeaderOffset: localOffset,
                dosTime: dosTime,
                dosDate: dosDate
            ))
        }

        let centralDirectoryOffset = try checkedUInt32(offset, "central directory offset")
        var centralDirectory = Data()
        for entry in written {
            let fileName = try utf8Bytes(entry.source.archivePath)
            centralDirectory.appendUInt32LE(0x0201_4B50)
            centralDirectory.appendUInt16LE(20)
            centralDirectory.appendUInt16LE(20)
            centralDirectory.appendUInt16LE(0x0800)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(entry.dosTime)
            centralDirectory.appendUInt16LE(entry.dosDate)
            centralDirectory.appendUInt32LE(entry.crc32)
            centralDirectory.appendUInt32LE(entry.compressedSize)
            centralDirectory.appendUInt32LE(entry.uncompressedSize)
            centralDirectory.appendUInt16LE(try checkedUInt16(UInt64(fileName.count), "file name length"))
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt32LE(entry.source.isDirectory ? 0x10 : 0)
            centralDirectory.appendUInt32LE(entry.localHeaderOffset)
            centralDirectory.append(fileName)
        }

        try handle.write(contentsOf: centralDirectory)
        offset += UInt64(centralDirectory.count)

        let entryCount = try checkedUInt16(UInt64(written.count), "entry count")
        let centralDirectorySize = try checkedUInt32(
            UInt64(centralDirectory.count),
            "central directory size"
        )

        var endRecord = Data()
        endRecord.appendUInt32LE(0x0605_4B50)
        endRecord.appendUInt16LE(0)
        endRecord.appendUInt16LE(0)
        endRecord.appendUInt16LE(entryCount)
        endRecord.appendUInt16LE(entryCount)
        endRecord.appendUInt32LE(centralDirectorySize)
        endRecord.appendUInt32LE(centralDirectoryOffset)
        endRecord.appendUInt16LE(0)
        try handle.write(contentsOf: endRecord)
        offset += UInt64(endRecord.count)

        _ = offset
    }

    private static func sourceEntries(
        under root: URL,
        archiveRootName: String,
        now: Date,
        fileManager: FileManager
    ) throws -> [SourceEntry] {
        var entries = [
            SourceEntry(
                archivePath: "\(archiveRootName)/",
                url: nil,
                isDirectory: true,
                modifiedAt: now
            )
        ]

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .contentModificationDateKey],
            options: []
        ) else {
            return entries
        }

        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .contentModificationDateKey
            ])
            let isDirectory = values.isDirectory == true
            guard isDirectory || values.isRegularFile == true else { continue }

            var archivePath = "\(archiveRootName)/\(try relativePath(for: url, under: root))"
            if isDirectory && !archivePath.hasSuffix("/") {
                archivePath.append("/")
            }
            entries.append(SourceEntry(
                archivePath: archivePath,
                url: isDirectory ? nil : url,
                isDirectory: isDirectory,
                modifiedAt: values.contentModificationDate ?? now
            ))
        }

        return [entries[0]] + entries.dropFirst().sorted { $0.archivePath < $1.archivePath }
    }

    private static func relativePath(for url: URL, under root: URL) throws -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else {
            throw ZipArchiveError.pathOutsideRoot(path)
        }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private static func utf8Bytes(_ string: String) throws -> Data {
        guard let data = string.data(using: .utf8) else {
            throw ZipArchiveError.invalidFileName(string)
        }
        try checkedUInt16(UInt64(data.count), "file name length")
        return data
    }

    private static func dosTimestamp(for date: Date) -> (time: UInt16, date: UInt16) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = min(max(components.year ?? 1980, 1980), 2107)
        let month = min(max(components.month ?? 1, 1), 12)
        let day = min(max(components.day ?? 1, 1), 31)
        let hour = min(max(components.hour ?? 0, 0), 23)
        let minute = min(max(components.minute ?? 0, 0), 59)
        let second = min(max(components.second ?? 0, 0), 59)

        let dosDate = UInt16((year - 1980) << 9 | month << 5 | day)
        let dosTime = UInt16(hour << 11 | minute << 5 | second / 2)
        return (dosTime, dosDate)
    }

    @discardableResult
    private static func checkedUInt16(_ value: UInt64, _ context: String) throws -> UInt16 {
        guard value <= UInt64(UInt16.max) else { throw ZipArchiveError.zip64Required(context) }
        return UInt16(value)
    }

    private static func checkedUInt32(_ value: UInt64, _ context: String) throws -> UInt32 {
        guard value <= UInt64(UInt32.max) else { throw ZipArchiveError.zip64Required(context) }
        return UInt32(value)
    }
}

private enum ZipArchiveError: LocalizedError {
    case couldNotRead(String)
    case invalidFileName(String)
    case pathOutsideRoot(String)
    case zip64Required(String)

    var errorDescription: String? {
        switch self {
        case .couldNotRead(let path):
            return "Could not read \(path) while exporting the library."
        case .invalidFileName(let name):
            return "Could not encode \(name) as a ZIP file name."
        case .pathOutsideRoot(let path):
            return "Refusing to export a file outside the Lists folder: \(path)."
        case .zip64Required(let context):
            return "The library is too large to export without ZIP64 support (\(context))."
        }
    }
}

private enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { byte in
        var crc = UInt32(byte)
        for _ in 0..<8 {
            if crc & 1 == 1 {
                crc = 0xEDB8_8320 ^ (crc >> 1)
            } else {
                crc >>= 1
            }
        }
        return crc
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = Self.table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
