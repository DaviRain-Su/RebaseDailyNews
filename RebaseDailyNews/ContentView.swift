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
        // 获取缓存中最新的新闻项的时间
        if let lastItemTime = allNewsItems.last?.time {
            let calendar = Calendar.current
            let currentDate = Date()
            
            // 计算当前日期的前一天
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: currentDate) else {
                return
            }
            
            // 如果缓存中最新的新闻项的时间早于前一天,则从服务器获取最新数据
            if lastItemTime < previousDay {
                fetchNewsItemsFromAPI()
            } else {
                // 从缓存加载数据
                loadNewsItemsFromCache()
            }
        } else {
            // 如果缓存为空,则从服务器获取最新数据
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
                            // 如果获取的数据数量等于分页大小,说明可能还有更多数据
                            // 可以在此处实现延迟加载的逻辑,例如在用户滚动到列表底部时再触发下一页的加载
                            // 这里简单地递增页码,继续获取下一页数据
                            page += 1
                            fetchPage()
                        } else {
                            // 数据获取完成
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
