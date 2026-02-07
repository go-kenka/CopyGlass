import SwiftUI

struct SettingsIconBadge: View {
    let systemName: String
    let colors: [Color]
    var size: CGFloat = 28
    var cornerRadius: CGFloat = 8
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                }
            
            Image(systemName: systemName)
                .font(.system(size: size * 0.52, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
        }
        .frame(width: size, height: size)
    }
}

struct SettingsSidebarRow: View {
    let title: String
    let iconSystemName: String
    let iconColors: [Color]
    
    var body: some View {
        HStack(spacing: 10) {
            SettingsIconBadge(systemName: iconSystemName, colors: iconColors, size: 20, cornerRadius: 6)
            Text(title)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

struct SettingsHeroCard: View {
    let title: String
    let subtitle: String
    let iconSystemName: String
    let iconColors: [Color]
    
    var body: some View {
        HStack(spacing: 16) {
            SettingsIconBadge(systemName: iconSystemName, colors: iconColors, size: 54, cornerRadius: 14)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 26, weight: .bold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer(minLength: 0)
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                }
        }
    }
}

struct SettingsNavigationRow: View {
    let title: String
    var subtitle: String? = nil
    let iconSystemName: String
    let iconColors: [Color]
    
    var body: some View {
        HStack(spacing: 12) {
            SettingsIconBadge(systemName: iconSystemName, colors: iconColors, size: 28, cornerRadius: 8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer(minLength: 0)
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

