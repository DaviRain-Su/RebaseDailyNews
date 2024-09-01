import SwiftUI
import Foundation
import Combine

struct NewsItemView: View {
    let newsItem: NewsItemDTO
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(newsItem.title)
                .font(.headline)
            Text(newsItem.introduce)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(newsItem.time, style: .date)
                .font(.caption)
                .foregroundColor(.secondary)
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
        guard let url = URL(string: "https://db.rebase.network/api/v1/geekdailies") else {
            return
        }
        
        var allItems: [NewsItemDTO] = []
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
                        allItems.append(contentsOf: newsItems)
                        
                        if let meta = newsResponse.meta {
                            print("Pagination: page \(meta.pagination.page), pageSize \(meta.pagination.pageSize), total \(meta.pagination.total)")
                        }
                        
                        let totalItems = self.allNewsItems.count + newsItems.count
                        print("Fetched \(newsItems.count) news items, total: \(totalItems)")
                        
                        if newsItems.count == pageSize {
                            page += 1
                            fetchPage()
                        } else {
                            print("Total items fetched: \(allItems.count)")
                            let sortedNewsItems = allItems.sorted { $0.time > $1.time }
                            self.allNewsItems = sortedNewsItems
                            self.newsItems = sortedNewsItems
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
}

struct ContentView: View {
    @StateObject private var viewModel = NewsViewModel()
    
    var body: some View {
        NavigationView {
            List(viewModel.newsItems) { item in
                NewsItemView(newsItem: item)
            }
            .navigationTitle("Rebase Daily News")
            .searchable(text: $viewModel.searchQuery)
            .onChange(of: viewModel.searchQuery) {
                viewModel.searchNewsItems()
            }
            .onAppear {
                viewModel.fetchNewsItems()
            }
        }
    }
}
