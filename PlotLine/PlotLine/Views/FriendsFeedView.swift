import SwiftUI

struct FriendsFeedView: View {
    @State private var posts: [FriendPost] = [] 
    @State private var isLoading = true
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
            NavigationView {
                VStack {
                    if isLoading {
                        ProgressView("Loading feed...")
                            .progressViewStyle(CircularProgressViewStyle())
                            .padding()
                    } else if posts.isEmpty {
                        Text("No posts yet.")
                            .font(.title3)
                            .foregroundColor(.gray)
                            .padding()
                    } else {
                        List(filteredPosts, id: \.id) { post in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(post.username)
                                        .font(.headline)
                                        .foregroundColor(.blue)
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
                                
                                // Like button
                                if post.username != username {
                                    HStack {
                                        Button(action: {
                                            likePost(post)
                                        }) {
                                            Image(systemName: post.likedBy?.contains(username) == true ? "heart.fill" : "heart")
                                                .foregroundColor(.red)
                                        }

                                        Text("\(post.likedBy?.count ?? 0)")
                                            .font(.caption)

                                        Spacer()
                                    }
                                }

                                // Comments display
                                if let comments = post.comments, !comments.isEmpty {
                                    ForEach(comments, id: \.self) { comment in
                                        Text(comment)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                // Comment box
                                if post.username != username {
                                    HStack {
                                        TextField("Add comment...", text: Binding(
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
                                    }
                                }

                                
                            }
                            .padding(.vertical, 6)
                        } .padding(.vertical, 12)
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
                .onAppear {
                    fetchFriendsFeed()
                }
            }
        }

    private func fetchFriendsFeed() {
        guard let url = URL(string: "http://localhost:8080/api/goals/friends-feed/\(username)") else {
            print("⚠️ Invalid Friends Feed URL")
            return
        }

        print("📡 Fetching friends feed from: \(url)")

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("❌ Network error fetching friends feed: \(error.localizedDescription)")
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("🔍 Friends Feed HTTP Status Code: \(httpResponse.statusCode)")
            }
            
            guard let data = data else {
                print("⚠️ No data received for friends feed")
                return
            }

            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601 // <- This line is key
                let decodedPosts = try decoder.decode([FriendPost].self, from: data)
                DispatchQueue.main.async {
                    self.posts = decodedPosts
                    self.isLoading = false
                    print("✅ Loaded \(self.posts.count) posts into Friends Feed")
                }
            } catch {
                print("❌ Error decoding friends feed: \(error)")
            }

        }.resume()
    }

    
    private func viewMyPosts() {
        print("View My Posts button tapped")
    }
    
    private func deletePost(_ post: FriendPost) {
        guard let url = URL(string: "http://localhost:8080/api/goals/friends-feed/\(username)/post/\(post.id)") else {
            print("❌ Invalid delete URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Error deleting post: \(error.localizedDescription)")
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                print("🗑️ Delete Post Status: \(httpResponse.statusCode)")
            }

            DispatchQueue.main.async {
                // Remove from local state so it disappears from the feed
                posts.removeAll { $0.id == post.id }
            }
        }.resume()
    }
    
    private func likePost(_ post: FriendPost) {
        guard let url = URL(string: "http://localhost:8080/api/goals/friends-feed/\(username)/post/\(post.id)/like") else {
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"

        URLSession.shared.dataTask(with: request) { _, _, _ in
            DispatchQueue.main.async {
                if let index = posts.firstIndex(where: { $0.id == post.id }) {
                    if posts[index].likedBy?.contains(username) == true {
                        posts[index].likedBy?.removeAll { $0 == username }
                    } else {
                        if posts[index].likedBy == nil {
                            posts[index].likedBy = []
                        }
                        posts[index].likedBy?.append(username)
                    }
                }
            }
        }.resume()
    }


    private func commentOnPost(_ post: FriendPost, _ comment: String) {
        guard let url = URL(string: "http://localhost:8080/api/goals/friends-feed/\(username)/post/\(post.id)/comment") else {
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["comment": comment]
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch { return }

        URLSession.shared.dataTask(with: request) { _, _, _ in
            DispatchQueue.main.async {
                newComments[post.id] = ""

                if let index = posts.firstIndex(where: { $0.id == post.id }) {
                    if posts[index].comments == nil {
                        posts[index].comments = []
                    }
                    posts[index].comments?.append("\(username): \(comment)")
                }
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


