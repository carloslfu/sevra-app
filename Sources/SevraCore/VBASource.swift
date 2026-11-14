import Foundation

/// Bounded MS-CFB/MS-OVBA source extraction. No VBA bytecode, forms or macros execute.
enum VBASource {
  static func modules(_ data: Data, cancellation: Cancellation) throws -> [(String, String)] {
    let streams = try CompoundStreams(data: data).read()
    guard let directory = streams["VBA/dir"] else {
      throw SevraError("vba_source", "The VBA source directory is missing.")
    }
    let dir = try decompress(directory)
    func matches(_ pattern: [UInt8]) -> [Int] {
      guard dir.count >= pattern.count else { return [] }
      return (0...(dir.count - pattern.count)).filter {
        Array(dir[$0..<($0 + pattern.count)]) == pattern
      }
    }
    let counts = matches([15, 0, 2, 0, 0, 0]).filter { i in
      i + 16 <= dir.count && Array(dir[(i + 8)..<(i + 14)]) == [19, 0, 2, 0, 0, 0]
    }
    try require(counts.count == 1, "vba_source", "VBA module records are missing or ambiguous.")
    var position = counts[0] + 16
    let count = Int(try u16(dir, counts[0] + 6))
    try require(count > 0 && count <= 128, "vba_limit", "VBA module count exceeds 128.")
    let codepages = matches([3, 0, 2, 0, 0, 0]).filter { $0 < counts[0] }
    let codepage = try codepages.last.map { Int(try u16(dir, $0 + 6)) } ?? 1252
    let encoding = String.Encoding(
      rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringConvertWindowsCodepageToEncoding(UInt32(codepage))))
    func decode(_ bytes: [UInt8]) throws -> String {
      guard let text = String(data: Data(bytes), encoding: encoding) else {
        throw SevraError("vba_source", "VBA source uses an unreadable character encoding.")
      }
      return text
    }
    var result: [(String, String)] = []
    var decodedBytes = 0
    for _ in 0..<count {
      try cancellation.check()
      var stream: String?
      var offset: Int?
      var ended = false
      for _ in 0..<24 {
        let kind = try u16(dir, position)
        let size = Int(try u32(dir, position + 2))
        position += 6
        try require(
          size <= 1_000_000 && position <= dir.count - size,
          "vba_source", "Truncated VBA module record.")
        let payload = Array(dir[position..<(position + size)])
        position += size
        switch kind {
        case 0x1a: stream = try decode(payload)
        case 0x31:
          try require(size == 4 && offset == nil, "vba_source", "Invalid VBA source offset.")
          offset = Int(try u32(payload, 0))
        case 0x2b: ended = true
        case 0x19, 0x47, 0x32, 0x1c, 0x48, 0x1e, 0x2c, 0x21, 0x22, 0x25, 0x28: break
        default: throw SevraError("vba_source", "Unknown VBA module record; source is incomplete.")
        }
        if ended { break }
      }
      guard ended, let stream, let offset, let bytes = streams["VBA/" + stream],
        offset < bytes.count
      else {
        throw SevraError("vba_source", "VBA module source is incomplete.")
      }
      let source = try decode(decompress(Data(bytes.dropFirst(offset))))
      decodedBytes += source.utf8.count
      try require(
        decodedBytes <= 16_000_000, "vba_limit", "Decoded VBA source exceeds its aggregate budget.")
      try require(!result.contains { $0.0 == stream }, "vba_source", "Duplicate VBA module source.")
      result.append((stream, source))
    }
    return result
  }

  static func decompress(_ data: Data) throws -> [UInt8] {
    let bytes = Array(data)
    try require(bytes.first == 1, "vba_source", "Invalid VBA compression signature.")
    var at = 1
    var output: [UInt8] = []
    while at < bytes.count {
      let header = try u16(bytes, at)
      let end = at + Int(header & 0x0fff) + 3
      try require(
        (header >> 12) & 7 == 3 && end <= bytes.count,
        "vba_source", "Invalid compressed VBA chunk.")
      at += 2
      let start = output.count
      if header & 0x8000 == 0 {
        try require(end - at == 4096, "vba_source", "Invalid uncompressed VBA chunk.")
        output += bytes[at..<end]
        at = end
      } else {
        while at < end {
          let flags = bytes[at]
          at += 1
          for bit in 0..<8 where at < end {
            if flags & (1 << bit) == 0 {
              output.append(bytes[at])
              at += 1
            } else {
              try require(at + 2 <= end, "vba_source", "Truncated VBA copy token.")
              let token = Int(try u16(bytes, at))
              at += 2
              let available = output.count - start
              var bits = 4
              while (1 << bits) < available { bits += 1 }
              try require(bits <= 12, "vba_source", "Oversized VBA chunk.")
              let lengthBits = 16 - bits
              let length = (token & ((1 << lengthBits) - 1)) + 3
              let distance = (token >> lengthBits) + 1
              try require(
                distance <= available && available + length <= 4096,
                "vba_source", "Invalid VBA back reference.")
              for _ in 0..<length { output.append(output[output.count - distance]) }
            }
            try require(output.count - start <= 4096, "vba_limit", "Oversized VBA chunk.")
          }
        }
      }
      try require(output.count <= 2_000_000, "vba_limit", "VBA source exceeds 2 MB.")
    }
    return output
  }
  static func u16(_ b: [UInt8], _ at: Int) throws -> UInt16 {
    try require(at >= 0 && at <= b.count - 2, "vba_source", "Truncated compound document.")
    return UInt16(b[at]) | UInt16(b[at + 1]) << 8
  }
  static func u32(_ b: [UInt8], _ at: Int) throws -> UInt32 {
    UInt32(try u16(b, at)) | UInt32(try u16(b, at + 2)) << 16
  }
}

private struct CompoundStreams {
  let data: Data
  func read() throws -> [String: Data] {
    let b = Array(data)
    try require(
      b.count >= 512 && b.count <= 32_000_000
        && Array(b.prefix(8)) == [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1],
      "vba_source", "Invalid VBA compound document.")
    func word(_ at: Int) throws -> Int { Int(try VBASource.u32(b, at)) }
    let major = try VBASource.u16(b, 26)
    let shift = try VBASource.u16(b, 30)
    try require(
      (major == 3 && shift == 9 || major == 4 && shift == 12)
        && VBASource.u16(b, 28) == 0xfffe && VBASource.u16(b, 32) == 6,
      "vba_source", "Invalid compound document sector format.")
    let size = 1 << Int(shift)
    let end = 0xffff_fffe
    let free = 0xffff_ffff
    func sector(_ number: Int) throws -> [UInt8] {
      try require(
        number >= 0 && number < b.count / size - 1,
        "vba_source", "Compound document sector is out of bounds.")
      return Array(b[((number + 1) * size)..<((number + 2) * size)])
    }
    var fatSectors: [Int] = []
    for i in 0..<109 {
      let n = try word(76 + i * 4)
      if n != free { fatSectors.append(n) }
    }
    var difat = try word(68)
    var seen = Set<Int>()
    for _ in 0..<(try word(72)) {
      try require(
        seen.count < 128 && seen.insert(difat).inserted,
        "vba_source", "Cyclic or oversized compound allocation table.")
      let s = try sector(difat)
      for i in 0..<(size / 4 - 1) {
        let n = Int(try VBASource.u32(s, i * 4))
        if n != free { fatSectors.append(n) }
      }
      difat = Int(try VBASource.u32(s, size - 4))
    }
    try require(
      fatSectors.count == word(44) && Set(fatSectors).count == fatSectors.count,
      "vba_source", "Invalid compound allocation table count.")
    var fat: [Int] = []
    for n in fatSectors {
      let s = try sector(n)
      for i in stride(from: 0, to: size, by: 4) { fat.append(Int(try VBASource.u32(s, i))) }
    }
    func chain(_ first: Int, table: [Int], block: (Int) throws -> [UInt8]) throws -> [UInt8] {
      var n = first
      var visited = Set<Int>()
      var result: [UInt8] = []
      while n != end {
        try require(
          table.indices.contains(n) && visited.insert(n).inserted
            && result.count <= 32_000_000 - size, "vba_source", "Invalid compound stream chain.")
        result += try block(n)
        n = table[n]
      }
      return result
    }
    let directory = try chain(word(48), table: fat, block: sector)
    try require(directory.count / 128 <= 4096, "vba_limit", "Too many compound streams.")
    func field(_ entry: Int, _ offset: Int) throws -> Int {
      Int(try VBASource.u32(directory, entry * 128 + offset))
    }
    let mini = try chain(field(0, 116), table: fat, block: sector)
    let miniBytes = try chain(word(60), table: fat, block: sector)
    var miniFAT: [Int] = []
    for i in stride(from: 0, to: miniBytes.count, by: 4) {
      miniFAT.append(Int(try VBASource.u32(miniBytes, i)))
    }
    var result: [String: Data] = [:]
    var visited = Set<Int>()
    var totalBytes = 0
    func walk(_ n: Int, prefix: String, depth: Int) throws {
      if n == free { return }
      try require(
        n >= 0 && n < directory.count / 128 && depth <= 64 && visited.insert(n).inserted,
        "vba_source", "Invalid compound directory tree.")
      let at = n * 128
      let length = Int(try VBASource.u16(directory, at + 64))
      try require(
        length >= 2 && length <= 64 && length % 2 == 0,
        "vba_source", "Invalid compound stream name.")
      let name = String(
        decoding: stride(from: at, to: at + length - 2, by: 2).map {
          UInt16(directory[$0]) | UInt16(directory[$0 + 1]) << 8
        }, as: UTF16.self)
      try require(
        !name.contains("/") && !name.contains("\\") && !name.contains("\0"),
        "vba_source", "Invalid compound stream name.")
      try walk(field(n, 68), prefix: prefix, depth: depth + 1)
      let path = prefix + name
      if directory[at + 66] == 1 {
        try walk(field(n, 76), prefix: path + "/", depth: depth + 1)
      } else if directory[at + 66] == 2 {
        let count = try field(n, 120)
        try require(
          count <= 2_000_000 && field(n, 124) == 0 && result[path] == nil,
          "vba_limit", "Oversized or duplicate VBA stream.")
        totalBytes += count
        try require(
          totalBytes <= 32_000_000, "vba_limit", "VBA streams exceed their aggregate budget.")
        let bytes: [UInt8]
        if count == 0 {
          bytes = []
        } else if count < 4096 {
          bytes = try chain(field(n, 116), table: miniFAT) { i in
            try require(i >= 0 && i < mini.count / 64, "vba_source", "Invalid mini stream sector.")
            return Array(mini[(i * 64)..<(i * 64 + 64)])
          }
        } else {
          bytes = try chain(field(n, 116), table: fat, block: sector)
        }
        try require(bytes.count >= count, "vba_source", "Truncated VBA stream.")
        result[path] = Data(bytes.prefix(count))
      }
      try walk(field(n, 72), prefix: prefix, depth: depth + 1)
    }
    try walk(field(0, 76), prefix: "", depth: 0)
    return result
  }
}
