import Foundation

extension Config {
    /// Known status pages that serve `/api/v2/summary.json` (checked 2026-11-10), grouped by area.
    /// Enabled ones make up the out-of-the-box menu.
    public static let catalog: [ServiceGroup] = [
        group("Git, CI", [
            ("GitHub", "https://www.githubstatus.com", true),
            ("Bitbucket", "https://bitbucket.status.atlassian.com", false),
            ("CircleCI", "https://status.circleci.com", false),
            ("Buildkite", "https://www.buildkitestatus.com", false),
            ("Travis CI", "https://www.traviscistatus.com", false),
            ("Codecov", "https://status.codecov.com", false),
            ("Snyk", "https://status.snyk.io", false),
        ]),
        group("AI", [
            ("OpenAI", "https://status.openai.com", true),
            ("Claude", "https://status.claude.com", true),
            ("Mistral", "https://status.mistral.ai", false),
            ("Groq", "https://groqstatus.com", false),
            ("Cohere", "https://status.cohere.com", false),
            ("Deepgram", "https://status.deepgram.com", false),
            ("ElevenLabs", "https://status.elevenlabs.io", false),
            ("Perplexity", "https://status.perplexity.com", false),
            ("Windsurf", "https://status.windsurf.com", false),
            ("Replit", "https://status.replit.com", false),
            ("Lovable", "https://status.lovable.dev", false),
            ("Bolt", "https://status.bolt.new", false),
        ]),
        group("Hosting, cloud", [
            ("Vercel", "https://www.vercel-status.com", true),
            ("Cloudflare", "https://www.cloudflarestatus.com", false),
            ("Netlify", "https://www.netlifystatus.com", false),
            ("Render", "https://status.render.com", false),
            ("Fly.io", "https://status.flyio.net", false),
            ("DigitalOcean", "https://status.digitalocean.com", false),
            ("Linode", "https://status.linode.com", false),
            ("HashiCorp", "https://status.hashicorp.com", false),
        ]),
        group("Databases", [
            ("Supabase", "https://status.supabase.com", true),
            ("PlanetScale", "https://www.planetscalestatus.com", false),
            ("MongoDB", "https://status.mongodb.com", false),
            ("Upstash", "https://status.upstash.com", false),
            ("Convex", "https://status.convex.dev", false),
            ("Pinecone", "https://status.pinecone.io", false),
        ]),
        group("Packages", [
            ("npm", "https://status.npmjs.org", false),
            ("PyPI", "https://status.python.org", false),
            ("RubyGems", "https://status.rubygems.org", false),
            ("Docker", "https://www.dockerstatus.com", false),
            ("JFrog", "https://status.jfrog.io", false),
        ]),
        group("Monitoring", [
            ("Sentry", "https://status.sentry.io", false),
            ("Grafana", "https://status.grafana.com", false),
            ("New Relic", "https://status.newrelic.com", false),
        ]),
        group("Auth, secrets, network", [
            ("Clerk", "https://status.clerk.com", false),
            ("1Password", "https://status.1password.com", false),
            ("Doppler", "https://www.dopplerstatus.com", false),
            ("Tailscale", "https://status.tailscale.com", false),
            ("ngrok", "https://status.ngrok.com", false),
        ]),
        group("Email, messaging, media", [
            ("Twilio", "https://status.twilio.com", false),
            ("Mailgun", "https://status.mailgun.com", false),
            ("Resend", "https://resend-status.com", false),
            ("Cloudinary", "https://status.cloudinary.com", false),
            ("Mapbox", "https://status.mapbox.com", false),
        ]),
        group("Work tools", [
            ("Linear", "https://linearstatus.com", false),
            ("Jira", "https://jira-software.status.atlassian.com", false),
            ("Figma", "https://status.figma.com", false),
            ("Postman", "https://status.postman.com", false),
            ("Expo", "https://status.expo.dev", false),
            ("Discord", "https://discordstatus.com", false),
            ("Zoom", "https://www.zoomstatus.com", false),
            ("Dropbox", "https://status.dropbox.com", false),
        ]),
    ]

    private static func group(_ name: String, _ services: [(String, String, Bool)]) -> ServiceGroup {
        ServiceGroup(name: name, services: services.map { ServiceConfig(name: $0.0, url: URL(string: $0.1)!, enabled: $0.2) })
    }
}
