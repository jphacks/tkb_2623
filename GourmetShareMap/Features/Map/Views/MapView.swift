//
//  MapView.swift
//  GourmetShareMap
//

import SwiftUI

struct MapView: View {
    @StateObject private var viewModel = MapViewModel()

    private let backgroundColor = Color(red: 0.984, green: 0.968, blue: 0.937)
    private let accentOrange = Color(red: 0.76, green: 0.35, blue: 0.22)

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                header
                categoryFilterBar
                ownerFilterRow
                mapCanvas
                if let selectedShop = viewModel.selectedShop {
                    SelectedShopCard(shop: selectedShop)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }

    private var header: some View {
        Text("02 マップ")
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(.black)
            .padding(.top, 8)
    }

    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ShopCategory.allCases) { category in
                    CategoryFilterChip(category: category, isSelected: viewModel.selectedCategory == category) {
                        viewModel.selectedCategory = category
                    }
                }
            }
        }
    }

    private var ownerFilterRow: some View {
        HStack(alignment: .center) {
            OwnerFilterControl(selection: $viewModel.ownerFilter)
            Spacer()
            MapLegendView()
        }
    }

    private var mapCanvas: some View {
        GeometryReader { geometry in
            ZStack {
                MapPlaceholderBackground()

                ForEach(viewModel.landmarks) { landmark in
                    Text(landmark.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.45))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.6), in: Capsule())
                        .position(
                            x: geometry.size.width * landmark.relativePosition.x,
                            y: geometry.size.height * landmark.relativePosition.y
                        )
                }

                ForEach(viewModel.filteredShops) { shop in
                    ShopPinView(shop: shop, isSelected: shop.id == viewModel.selectedShopID)
                        .position(
                            x: geometry.size.width * shop.relativePosition.x,
                            y: geometry.size.height * shop.relativePosition.y
                        )
                        .onTapGesture {
                            viewModel.selectShop(shop)
                        }
                }

                mapControls
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(16)

                Text("Google Maps 実装待ち(仮表示)")
                    .font(.system(size: 10))
                    .foregroundStyle(.black.opacity(0.35))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private var mapControls: some View {
        VStack(spacing: 12) {
            Button {
                // TODO: 現在地取得機能を実装する。
            } label: {
                Image(systemName: "location.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.black.opacity(0.7))
                    .frame(width: 44, height: 44)
                    .background(Color.white, in: Circle())
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
            }

            Button {
                // TODO: 店舗登録画面ができたら遷移させる。
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(accentOrange, in: Circle())
                    .shadow(color: accentOrange.opacity(0.4), radius: 8, y: 4)
            }
        }
    }
}

#Preview {
    MapView()
}
