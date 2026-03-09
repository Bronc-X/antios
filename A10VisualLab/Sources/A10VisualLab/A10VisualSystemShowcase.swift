import SwiftUI

struct A10VisualSystemShowcase: View {
    let language: AppLanguage

    init(language: AppLanguage = .zhHans) {
        self.language = language
    }

    var body: some View {
        let introCopy = A10VisualRecipeFactory.intro()
        let maxCopy = A10VisualRecipeFactory.maxSection()
        let insightCopy = A10VisualRecipeFactory.insightSection()

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                intro(copy: introCopy)

                A10DashboardSpatialHeroCard(
                    model: A10VisualRecipeFactory.dashboard(language: language),
                    language: language
                )

                sectionHeader(
                    title: maxCopy.title.resolve(language),
                    subtitle: maxCopy.subtitle.resolve(language)
                )

                A10FloatingMenuScaffold(
                    model: A10VisualRecipeFactory.maxLight(language: language),
                    language: language
                )

                A10FloatingMenuScaffold(
                    model: A10VisualRecipeFactory.maxDark(language: language),
                    language: language
                )

                sectionHeader(
                    title: insightCopy.title.resolve(language),
                    subtitle: insightCopy.subtitle.resolve(language)
                )

                A10EmotionWheelScaffold(
                    model: A10VisualRecipeFactory.insight(language: language),
                    language: language
                )
            }
            .padding(20)
        }
        .background(A10MistCanvas().ignoresSafeArea())
    }

    private func intro(copy: A10ShowcaseCopyBlock) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(copy.title.resolve(language))
                .font(A10SpatialTypography.title(28, weight: .bold))
                .foregroundColor(Color.black.opacity(0.82))

            Text(copy.subtitle.resolve(language))
                .font(A10SpatialTypography.body(14, weight: .medium))
                .foregroundColor(Color.black.opacity(0.52))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.62))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.46), lineWidth: 1)
                )
        )
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(A10SpatialTypography.title(18, weight: .semibold))
                .foregroundColor(Color.black.opacity(0.78))
            Text(subtitle)
                .font(A10SpatialTypography.body(13, weight: .medium))
                .foregroundColor(Color.black.opacity(0.46))
        }
    }
}

struct A10VisualSystemShowcase_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            A10VisualSystemShowcase(language: .zhHans)
                .previewDisplayName("A10 Visual System ZH")

            A10VisualSystemShowcase(language: .en)
                .previewDisplayName("A10 Visual System EN")
        }
    }
}
