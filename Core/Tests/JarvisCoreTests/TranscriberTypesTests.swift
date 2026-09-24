import Testing

@testable import JarvisCore

@Suite struct TranscriberTypesTests {
    @Test func realTimeFactorIsZeroWithoutAudio() {
        var t = ChunkTimings()
        t.totalSeconds = 1
        #expect(t.realTimeFactor == 0)
    }

    @Test func realTimeFactorDividesWallClockByAudio() {
        var t = ChunkTimings()
        t.audioSeconds = 10
        t.totalSeconds = 2
        #expect(t.realTimeFactor == 0.2)
    }
}
