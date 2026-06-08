
import SwiftUI

func loadJotNotes() -> [JotNote] {
    guard let data = UserDefaults.standard.data(forKey: AppStorageKey.jotNotes),
          let notes = try? JSONDecoder().decode([JotNote].self, from: data) else {
        return []
    }
    return notes
}
