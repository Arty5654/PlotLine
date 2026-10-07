import SwiftUI

struct FriendsFeedView: View {
    @State private var posts: [FriendPost]
    @State private var isLoading: Bool

    /// posts to show before the first load (Xcode previews)
    init(previewPosts: [FriendPost] = []) {
        _posts = State(initialValue: previewPosts)
        _isLoading = State(initialValue: previewPosts.isEmpty)
    }
    @State private var showOnlyMyPosts = false
    @State private var newComments: [UUID: String] = [:]

    
    /* Fetch the logged-in username from UserDefaults */
    private var username: String {
        return UserDefaults.standard.string(forKey: "loggedInUsername") ?? "Guest"
    }
    
    private var filteredPosts: [FriendPost] {
        if showOnlyMyPosts {
            return posts.filter { $0.username == username }
        } else {
            return posts.filter { $0.username != username }
        }
    }


    var body: some View {
        VStack(spacing: 0) {
            Picker("Show", selection: $showOnlyMyPosts) {
                Text("Friends").tag(false)
                Text("My posts").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, PLSpacing.lg)
            .padding(.vertical, PLSpacing.sm)

            ScrollView {
                VStack(spacing: PLSpacing.md) {
                    if isLoading {
                        ProgressView("Loading feed…")
                            .padding(.top, PLSpacing.lg)
                    } else if filteredPosts.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "newspaper")
                                .font(.title2)
                                .foregroundColor(PLColor.textSecondary)
                            Text(showOnlyMyPosts ? "You haven't shared any goals yet." : "No posts from friends yet.")
                                .font(.headline)
                            Text(showOnlyMyPosts ? "Share a long-term goal from Goals." : "When friends share goals, they show up here.")
                                .font(.subheadline)
                                .foregroundColor(PLColor.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, PLSpacing.sm)
                        .plCard()
                    } else {
                        ForEach(filteredPosts, id: \.id) { post in
                            postCard(post)
                        }
                    }
                }
                .padding(.horizontal, PLSpacing.lg)
                .padding(.bottom, PLSpacing.lg)
            }
            .refreshable { fetchFriendsFeed() }
        }
        .navigationTitle("Friends Feed")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            fetchFriendsFeed()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                fetchFriendsFeed()
            }
        }
    }

    private func postCard(_ post: FriendPost) -> some View {
        let isMine = post.username == username
        let likes = post.likedBy ?? []
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                FriendProfilePicture(username: post.username)
                    .frame(width: 32, height: 32)
                Text(post.username)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if isMine {
                    Menu {
                        Button("Unshare", role: .destructive) { deletePost(post) }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundColor(PLColor.textSecondary)
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("Post options")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(post.goal.title)
                    .font(.headline)
                ForEach(post.goal.steps) { step in
                    HStack(spacing: 8) {
                        Image(systemName: step.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(step.isCompleted ? PLColor.success : Color(.tertiaryLabel))
                        Text(step.name)
                            .foregroundColor(step.isCompleted ? PLColor.textPrimary : PLColor.textSecondary)
                    }
                    .font(.subheadline)
                }
                if let comment = post.comment, !comment.isEmpty {
                    Text(comment)
                        .font(.subheadline)
                        .foregroundColor(PLColor.textSecondary)
                }
            }

            Divider()

            HStack(spacing: 6) {
                if isMine {
                    Image(systemName: likes.isEmpty ? "heart" : "heart.fill")
                        .foregroundColor(.red)
                } else {
                    Button { likePost(post) } label: {
                        Image(systemName: likes.contains(username) ? "heart.fill" : "heart")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(likes.contains(username) ? "Unlike" : "Like")
                }
                Text("\(likes.count) \(likes.count == 1 ? "like" : "likes")")
                    .font(.footnote)
                    .foregroundColor(PLColor.textSecondary)
                if isMine, !likes.isEmpty {
                    Text("· \(likes.joined(separator: ", "))")
                        .font(.footnote)
                        .foregroundColor(PLColor.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
            }

            if let comments = post.comments, !comments.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(comments, id: \.self) { comment in
                        commentText(comment)
                    }
                }
            }

            // comment box (friends' posts only)
            if !isMine {
                let draft = newComments[post.id] ?? ""
                HStack(spacing: 8) {
                    TextField("Add a comment…", text: Binding(
                        get: { newComments[post.id] ?? "" },
                        set: { newComments[post.id] = $0 }
                    ))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemBackground))
                    .clipShape(Capsule())

                    Button {
                        let text = draft.trimmingCharacters(in: .whitespaces)
                        if !text.isEmpty { commentOnPost(post, text) }
                    } label: {
                        Image(systemName: "paperplane.fill")
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("Send comment")
                }
            }
        }
        .plCard()
    }

    // "name: text" with the name in bold
    private func commentText(_ comment: String) -> some View {
        let parts = comment.split(separator: ":", maxSplits: 1).map(String.init)
        if parts.count == 2 {
            return Text(parts[0]).font(.footnote.weight(.semibold)) + Text(":" + parts[1]).font(.footnote)
        }
        return Text(comment).font(.footnote)
    }

    private func fetchFriendsFeed() {
        if posts.isEmpty { isLoading = true }
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/goals/friends-feed/\(username)") else {
            isLoading = false
            return
        }

        var request = URLRequest(url: url)
        BackendConfig.addApiKey(to: &request)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                AppBanner.report("load the goal feed", error, retry: { self.fetchFriendsFeed() })
                DispatchQueue.main.async { self.isLoading = false }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async { self.isLoading = false }
                return
            }

            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let decodedPosts = try decoder.decode([FriendPost].self, from: data)
                DispatchQueue.main.async {
                    self.posts = decodedPosts
                    self.isLoading = false
                }
            } catch {
                AppBanner.report("load the goal feed", error, retry: { self.fetchFriendsFeed() })
                DispatchQueue.main.async { self.isLoading = false }
            }
        }.resume()
    }

    
    private func deletePost(_ post: FriendPost) {
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/goals/friends-feed/\(username)/post/\(post.id)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        BackendConfig.addApiKey(to: &request)
        URLSession.shared.dataTask(with: request) { _, response, error in
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                AppBanner.report("delete your post", error, retry: { self.deletePost(post) })
                return
            }
            DispatchQueue.main.async { self.fetchFriendsFeed() }
        }.resume()
    }

    private func likePost(_ post: FriendPost) {
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/goals/friends-feed/\(username)/post/\(post.id)/like") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        BackendConfig.addApiKey(to: &request)
        URLSession.shared.dataTask(with: request) { _, response, error in
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                AppBanner.report("update your like", error)
                return
            }
            DispatchQueue.main.async { self.fetchFriendsFeed() }
        }.resume()
    }

    private func commentOnPost(_ post: FriendPost, _ comment: String) {
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/goals/friends-feed/\(username)/post/\(post.id)/comment") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        BackendConfig.addApiKey(to: &request)
        guard let body = try? JSONEncoder().encode(["comment": comment]) else { return }
        request.httpBody = body
        URLSession.shared.dataTask(with: request) { _, response, error in
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                AppBanner.report("post your comment", error) // the comment stays in the box
                return
            }
            DispatchQueue.main.async {
                self.newComments[post.id] = ""
                self.fetchFriendsFeed()
            }
        }.resume()
    }



    
}

struct FriendPost: Identifiable, Codable {
    let id: UUID
    let username: String
    var goal: LongTermGoal
    var comment: String? // original post message

    var likedBy: [String]?
    var comments: [String]?
}


