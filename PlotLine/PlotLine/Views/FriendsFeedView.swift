import SwiftUI

struct FriendsFeedView: View {
    @State private var posts: [FriendPost] = []
    @State private var isLoading = true
    @State private var showOnlyMyPosts = false
    @State private var newComments: [UUID: String] = [:]

    @Environment(\.colorScheme) var colorScheme
    private var adaptiveTextColor: Color { colorScheme == .dark ? .white : .blue }
    
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
            VStack {
                    if isLoading {
                        ProgressView("Loading feed...")
                            .progressViewStyle(CircularProgressViewStyle())
                            .padding()
                    } else if filteredPosts.isEmpty {
                        Text(showOnlyMyPosts ? "You haven't shared any goals yet." : "No posts from friends yet.")
                            .font(.title3)
                            .foregroundColor(.gray)
                            .padding()
                    } else {
                        List(filteredPosts, id: \.id) { post in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(post.username)
                                        .font(.headline)
                                        .foregroundColor(adaptiveTextColor)
                                    Spacer()
                                }
                                
                                Text(post.goal.title)
                                    .font(.title3)
                                    .bold()
                                
                                ForEach(post.goal.steps) { step in
                                    Text("- \(step.name)")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                
                                if let comment = post.comment {
                                    Text(comment)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                
                                if post.username == username {
                                    Button(role: .destructive) {
                                        deletePost(post)
                                    } label: {
                                        Text("Unshare")
                                            .font(.caption)
                                            .foregroundColor(.red)
                                    }
                                }
                                
                                Divider()

                                // Likes row
                                HStack(spacing: 6) {
                                    if post.username == username {
                                        Image(systemName: (post.likedBy?.isEmpty ?? true) ? "heart" : "heart.fill")
                                            .foregroundColor(.red)
                                    } else {
                                        Button(action: { likePost(post) }) {
                                            Image(systemName: post.likedBy?.contains(username) == true ? "heart.fill" : "heart")
                                                .foregroundColor(.red)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    Text("\(post.likedBy?.count ?? 0) \(post.likedBy?.count == 1 ? "like" : "likes")")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }

                                // Who liked (own posts only)
                                if post.username == username,
                                   let likers = post.likedBy, !likers.isEmpty {
                                    Text("Liked by \(likers.joined(separator: ", "))")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .italic()
                                }

                                // Comments
                                if let comments = post.comments, !comments.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ForEach(comments, id: \.self) { comment in
                                            Text(comment)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }

                                // Comment input (friends' posts only)
                                if post.username != username {
                                    HStack {
                                        TextField("Add a comment…", text: Binding(
                                            get: { newComments[post.id] ?? "" },
                                            set: { newComments[post.id] = $0 }
                                        ))
                                        .textFieldStyle(RoundedBorderTextFieldStyle())

                                        Button("Send") {
                                            let text = newComments[post.id, default: ""].trimmingCharacters(in: .whitespaces)
                                            if !text.isEmpty {
                                                commentOnPost(post, text)
                                            }
                                        }
                                        .disabled((newComments[post.id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                                    }
                                }

                                
                            }
                            .padding(.vertical, 6)
                        }
                        .refreshable { fetchFriendsFeed() }
                        .padding(.vertical, 12)
                    }

                    // Button to view my posts
                    Button(action: {
                        showOnlyMyPosts.toggle()
                    }) {
                        Text(showOnlyMyPosts ? "View Friends' Posts" : "View My Posts")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue)
                            .cornerRadius(10)
                            .padding()
                    }


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
                print("❌ Network error fetching friends feed: \(error.localizedDescription)")
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
                print("❌ Error decoding friends feed: \(error)")
                DispatchQueue.main.async { self.isLoading = false }
            }
        }.resume()
    }

    
    private func deletePost(_ post: FriendPost) {
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/goals/friends-feed/\(username)/post/\(post.id)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        BackendConfig.addApiKey(to: &request)
        URLSession.shared.dataTask(with: request) { _, response, _ in
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            DispatchQueue.main.async { self.fetchFriendsFeed() }
        }.resume()
    }

    private func likePost(_ post: FriendPost) {
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/goals/friends-feed/\(username)/post/\(post.id)/like") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        BackendConfig.addApiKey(to: &request)
        URLSession.shared.dataTask(with: request) { _, response, _ in
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
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
        URLSession.shared.dataTask(with: request) { _, response, _ in
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
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


