import SwiftUI

struct CategoriesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedCategory: CategoryFilter = CategoryFilter.defaults[0]
    @State private var items: [DoubanItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let columns = [
        GridItem(.adaptive(minimum: 240, maximum: 280), spacing: 36)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    Text("Categories")
                        .font(.largeTitle.bold())

                    ScrollView(.horizontal) {
                        HStack(spacing: 16) {
                            ForEach(appState.categories) { cat in
                                Button {
                                    selectedCategory = cat
                                    Task { await loadCategory(cat) }
                                } label: {
                                    Text(cat.label)
                                        .padding(.horizontal, 18)
                                        .padding(.vertical, 8)
                                        .background(selectedCategory.id == cat.id ? Color.blue.opacity(0.35) : Color.clear)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.vertical, 12)
                    }

                    if isLoading {
                        ProgressView("Loading \(selectedCategory.label)...")
                    } else if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }

                    LazyVGrid(columns: columns, spacing: 40) {
                        ForEach(items) { item in
                            NavigationLink {
                                DoubanTitleResolverView(item: item)
                            } label: {
                                PosterCardView(
                                    title: item.title,
                                    subtitle: item.year ?? selectedCategory.label,
                                    rawPosterURL: item.poster,
                                    ratingBadge: item.rate,
                                    progress: nil
                                )
                            }
                            .buttonStyle(.card)
                        }
                    }
                }
                .padding(56)
            }
        }
        .task {
            if let first = appState.categories.first {
                selectedCategory = first
                await loadCategory(first)
            }
        }
    }

    private func loadCategory(_ category: CategoryFilter) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            items = try await appState.client.fetchDouban(
                type: category.type,
                tag: category.tag,
                pageSize: 24,
                pageStart: 0
            )
            if items.isEmpty {
                errorMessage = "No items returned for \(category.label)."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
