import Testing

@testable import JarvisCore

/// Same strings and thresholds as the Python `_is_hallucination` / `_is_near_duplicate`.
@Suite struct HallucinationFilterTests {
    @Test func knownArtifactsAreStripped() {
        #expect(HallucinationFilter.strip("Ahoj světe. Titulky vytvořil JohnyX") == "Ahoj světe.")
        #expect(HallucinationFilter.strip("Thank you for watching") == "")
        #expect(HallucinationFilter.strip("Navštivte www.example.com dnes") == "Navštivte  dnes")
    }

    @Test func emptyOrArtifactOnlyIsHallucination() {
        #expect(HallucinationFilter.isHallucination(""))
        #expect(HallucinationFilter.isHallucination("   "))
        #expect(HallucinationFilter.isHallucination("Titulky vytvořil JohnyX"))
        #expect(HallucinationFilter.isHallucination("Děkuji za pozornost"))
    }

    @Test func wordLoopsAreHallucinations() {
        #expect(HallucinationFilter.isHallucination("elected elected elected elected elected elected"))
        #expect(HallucinationFilter.isHallucination("up up up up"))
        #expect(HallucinationFilter.isHallucination("I think I think I think I think I think"))
        #expect(
            HallucinationFilter.isHallucination("the shape of the shape of the shape of the shape of the shape of the"))
    }

    @Test func normalSpeechPasses() {
        #expect(
            !HallucinationFilter.isHallucination(
                "Dobře, takže setup jednou, sunny voice, setup model, start voice server."))
        #expect(!HallucinationFilter.isHallucination("Určitě by mě zajímalo, jak to zrychlit."))
        #expect(!HallucinationFilter.isHallucination("Ano ano ano"))  // < 4 words, allowed
        #expect(!HallucinationFilter.isHallucination("Jo."))
        #expect(!HallucinationFilter.isHallucination("Ne"))
        #expect(HallucinationFilter.isHallucination("..."))
    }

    @Test func nearDuplicateDetection() {
        #expect(
            HallucinationFilter.isNearDuplicate(
                "otevři prosím pull request v githubu", "Otevři prosím pull request v GitHubu."))
        #expect(!HallucinationFilter.isNearDuplicate("otevři prosím pull request", "nasaď to na BTP prosím"))
        #expect(!HallucinationFilter.isNearDuplicate("ano ano", "ano ano"))  // too short to judge
    }
}

@Suite struct TranscriptAssemblerTests {
    @Test func assemblesInIndexOrderRegardlessOfArrival() {
        var a = TranscriptAssembler()
        a.add(index: 2, text: "třetí část")
        a.add(index: 0, text: "první část")
        a.add(index: 1, text: "druhá část")
        #expect(a.text == "první část druhá část třetí část")
        #expect(a.acceptedChunkCount == 3)
    }

    @Test func dropsHallucinationsAndDuplicates() {
        var a = TranscriptAssembler()
        #expect(a.add(index: 0, text: "Otevři prosím pull request v GitHubu") != nil)
        #expect(a.add(index: 1, text: "otevři prosím pull request v githubu.") == nil)  // near-duplicate
        #expect(a.add(index: 2, text: "Titulky vytvořil JohnyX") == nil)
        #expect(a.add(index: 3, text: "a nasaď to na BTP. Titulky vytvořil JohnyX") == "a nasaď to na BTP.")
        #expect(a.text == "Otevři prosím pull request v GitHubu a nasaď to na BTP.")
    }
}
