import SwiftUI
import Foundation
import Combine
import WebKit

struct NewsItemView: View {
    let newsItem: NewsItemDTO
    
    var body: some View {
        NavigationLink(destination: WebView(url: URL(string: newsItem.url)!)) {
            VStack(alignment: .leading, spacing: 8) {
                Text(newsItem.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(newsItem.introduce)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                HStack {
                    Text(newsItem.time, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 8)
        }
    }
}

struct NewsItemDTO: Identifiable, Codable {
    let id: Int
    let attributes: NewsItemAttributes
    
    var title: String { attributes.title }
    var url: String { attributes.url }
    var time: Date {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.date(from: attributes.time) ?? Date()
    }
    var introduce: String { attributes.introduce ?? "" }
}

struct NewsResponse: Codable {
    let data: [NewsItemDTO]?
    let error: NewsError?
    let meta: NewsMeta?
}

struct NewsMeta: Codable {
    let pagination: Pagination
}

struct Pagination: Codable {
    let page: Int
    let pageSize: Int
    let pageCount: Int
    let total: Int
}

struct NewsError: Codable {
    let status: Int
    let name: String
    let message: String
}

struct NewsItemAttributes: Codable {
    let title: String
    let url: String
    let time: String
    let introduce: String?
}

class NewsViewModel: ObservableObject {
    @Published var newsItems: [NewsItemDTO] = []
    @Published var searchQuery = ""
    
    private var allNewsItems: [NewsItemDTO] = []
    private var cancellables = Set<AnyCancellable>()
    
    func fetchNewsItems() {
        // 检查上次更新时间
        let lastUpdated = UserDefaults.standard.object(forKey: "lastUpdated") as? Date
        let currentDate = Date()
        
        if let lastUpdated = lastUpdated, Calendar.current.isDate(lastUpdated, inSameDayAs: currentDate) {
            // 如果在同一天,从缓存加载数据
            loadNewsItemsFromCache()
            
            // 检查缓存中数据量是否足够
            if allNewsItems.count < 100 {
                // 如果缓存中的数据量不足,重置缓存并重新获取数据
                resetCache()
                fetchNewsItemsFromAPI()
            }
        } else {
            // 如果不在同一天或没有缓存数据,从服务器获取数据
            fetchNewsItemsFromAPI()
        }
    }
    
    func fetchNewsItemsFromAPI() {
        guard let url = URL(string: "https://db.rebase.network/api/v1/geekdailies") else {
            return
        }
        
        var page = 1
        let pageSize = 100
        var retryCount = 0
        let maxRetryCount = 3
        
        func fetchPage() {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.queryItems = [
                URLQueryItem(name: "pagination[page]", value: "\(page)"),
                URLQueryItem(name: "pagination[pageSize]", value: "\(pageSize)")
            ]
            
            guard let pageURL = components?.url else {
                print("Invalid URL")
                return
            }
            
            URLSession.shared.dataTaskPublisher(for: pageURL)
                .map { $0.data }
                .receive(on: DispatchQueue.main)
                .sink { completion in
                    switch completion {
                    case .failure(let error):
                        print("Error fetching news items: \(error)")
                    case .finished:
                        break
                    }
                } receiveValue: { data in
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print("Received JSON response: \(jsonString)")
                    }
                    
                    do {
                        let newsResponse = try JSONDecoder().decode(NewsResponse.self, from: data)
                        
                        if let error = newsResponse.error {
                            print("API returned an error: \(error.status) - \(error.name) - \(error.message)")
                            
                            if error.status == 500 && retryCount < maxRetryCount {
                                retryCount += 1
                                print("Retrying request in 5 seconds... (Retry count: \(retryCount))")
                                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                                    fetchPage()
                                }
                            }
                            
                            return
                        }
                        
                        let newsItems = newsResponse.data ?? []
                        self.allNewsItems.append(contentsOf: newsItems)
                        self.newsItems = self.allNewsItems.sorted { $0.time > $1.time }
                        
                        if let meta = newsResponse.meta {
                            print("Pagination: page \(meta.pagination.page), pageSize \(meta.pagination.pageSize), total \(meta.pagination.total)")
                        }
                        
                        print("Fetched \(newsItems.count) news items, total: \(self.newsItems.count)")
                        
                        if newsItems.count == pageSize {
                            page += 1
                            fetchPage()
                        } else {
                            print("Total items fetched: \(self.allNewsItems.count)")
                            self.saveNewsItemsToCache(self.allNewsItems)
                        }
                    } catch {
                        print("Error decoding JSON: \(error)")
                    }
                }
                .store(in: &self.cancellables)
        }
        
        fetchPage()
    }
    
    func searchNewsItems() {
        if searchQuery.isEmpty {
            newsItems = allNewsItems
        } else {
            newsItems = allNewsItems.filter { item in
                item.title.localizedCaseInsensitiveContains(searchQuery) ||
                item.introduce.localizedCaseInsensitiveContains(searchQuery)
            }
        }
    }
    
    func loadNewsItemsFromCache() {
        if let data = UserDefaults.standard.data(forKey: "cachedNewsItems") {
            let decoder = JSONDecoder()
            if let cachedNewsItems = try? decoder.decode([NewsItemDTO].self, from: data) {
                self.allNewsItems = cachedNewsItems
                self.newsItems = cachedNewsItems
                print("Loaded \(cachedNewsItems.count) news items from cache")
            } else {
                print("Failed to decode cached news items")
            }
        } else {
            print("No cached news items found")
        }
    }
    
    func saveNewsItemsToCache(_ newsItems: [NewsItemDTO]) {
        let encoder = JSONEncoder()
        if let encodedData = try? encoder.encode(newsItems) {
            UserDefaults.standard.set(encodedData, forKey: "cachedNewsItems")
            UserDefaults.standard.set(Date(), forKey: "lastUpdated")
            print("Saved \(newsItems.count) news items to cache")
        } else {
            print("Failed to encode news items for caching")
        }
    }
    
    func resetCache() {
        UserDefaults.standard.removeObject(forKey: "cachedNewsItems")
        UserDefaults.standard.removeObject(forKey: "lastUpdated")
        allNewsItems.removeAll()
        newsItems.removeAll()
        print("Cache reset")
    }
    
    func sortNewsItems(by sortOrder: SortOrder) {
        switch sortOrder {
        case .ascending:
            newsItems.sort { $0.time < $1.time }
        case .descending:
            newsItems.sort { $0.time > $1.time }
        }
    }
}

#if os(iOS)
struct WebView: UIViewRepresentable {
    let url: URL
    
    func makeUIView(context: Context) -> WKWebView {
        return WKWebView()
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        let request = URLRequest(url: url)
        uiView.load(request)
    }
}
#elseif os(macOS)
struct WebView: NSViewRepresentable {
    let url: URL
    
    func makeNSView(context: Context) -> WKWebView {
        return WKWebView()
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        let request = URLRequest(url: url)
        nsView.load(request)
    }
}
#endif

struct ContentView: View {
    @StateObject private var viewModel = NewsViewModel()
    @State private var selectedSortOrder: SortOrder = .descending
    
    var body: some View {
        NavigationView {
            List(viewModel.newsItems) { item in
                NewsItemView(newsItem: item)
            }
            .navigationTitle("Rebase Daily News")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $viewModel.searchQuery)
            .onChange(of: viewModel.searchQuery) {
                viewModel.searchNewsItems()
            }
            .refreshable {
                viewModel.fetchNewsItems()
            }
            .onAppear {
                viewModel.fetchNewsItems()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Picker("Sort Order", selection: $selectedSortOrder) {
                            Text("Ascending").tag(SortOrder.ascending)
                            Text("Descending").tag(SortOrder.descending)
                        }
                        .onChange(of: selectedSortOrder) { _ in
                            viewModel.sortNewsItems(by: selectedSortOrder)
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
            }
        }
    }
}

enum SortOrder {
    case ascending
    case descending
}
