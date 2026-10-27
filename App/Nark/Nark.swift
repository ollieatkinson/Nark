import NarkApplication

@main
enum Nark {

    @MainActor static func main() async {
        await NarkApplication.main()
    }
}
