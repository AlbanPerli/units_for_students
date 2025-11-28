//
//  ContentView.swift
//  SimpleRvr
//
//  Created by Al on 13/11/2025.
//

import SwiftUI
import Synchrosphere
import Pappe

class RobotController: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var deviceName: String = ""
    @Published var heading: Int = 0     // heading en degrés 0-359
    @Published var speed: Int = 0     // vitesse
    @Published private(set) var currentCommand: Command = .none

    enum Command {
        case none
        case forward
        case back
        case turn
    }

    private let engine = SyncsEngine()
    private var controller: SyncsController?
    private var config: SyncsControllerConfig?

    func connect() {
        let cfg = SyncsControllerConfig(deviceSelector: .anyRVR)
        self.config = cfg

        controller = engine.makeController(for: cfg) { names, ctx in
            activity(names.Main, []) { _ in
                // Boucle permanente pour rester connecté et exécuter les commandes
                `repeat` {
                    `if` { self.currentCommand == .forward } then: {
                        run(Syncs.RollForSeconds, [SyncsSpeed(UInt16(self.speed)), SyncsHeading(UInt16(self.heading)), SyncsDir.forward, 1])
                    }
                    `if` { self.currentCommand == .back } then: {
                        run(Syncs.RollForSeconds, [SyncsSpeed(UInt16(self.speed)), SyncsHeading(UInt16(self.heading)), SyncsDir.backward, 1])
                    }
                    `if` { self.currentCommand == .turn } then: {
                        // vitesse 0 pour tourner sur place
                        run(Syncs.RollForSeconds, [SyncsSpeed(UInt16(self.speed)), SyncsHeading(UInt16(self.heading)), SyncsDir.forward, 1])
                    }
                    // On remet à none après commande
                    exec { self.currentCommand = .none }
                    // Pause ou attente avant boucle suivante
                    run(Syncs.WaitMilliseconds, [10])
                } until: { false }
            }
        }

        controller?.start()
        DispatchQueue.main.async {
            self.isConnected = true
        }
    }

    func sendForward() {
        guard isConnected else { return }
        currentCommand = .forward
        speed = 100
    }

    func sendBack() {
        guard isConnected else { return }
        currentCommand = .back
        speed = 100
    }

    func turnLeft() {
        guard isConnected else { return }
        // Décrémente de 2°, maintien dans 0-359
        heading = (heading - 2 + 360) % 360
        print("Heading \(heading)°")
        // commande pour tourner sur place : vitesse 0, direction forward (ou backward si besoin)
        currentCommand = .turn
        speed = 0
    }

    func turnRight() {
        guard isConnected else { return }
        heading = (heading + 2) % 360
        print("Heading \(heading)°")
        currentCommand = .turn
        speed = 0
    }

    func disconnect() {
        controller?.stop()
        controller = nil
        DispatchQueue.main.async {
            self.isConnected = false
        }
    }
}

struct ContentView: View {
    @StateObject private var vm = RobotController()
    @StateObject private var cameraModel = CameraViewModel()
    @State private var leftTimer: Timer?
    @State private var rightTimer: Timer?

    var body: some View {
        VStack(spacing: 20) {

            GeometryReader { geo in
                ZStack {
                    CameraPreview(session: cameraModel.session, model: cameraModel).ignoresSafeArea()
                    ForEach(cameraModel.detectedRects, id: \.self) { normRect in
                        let rect = rectFromNormalized(normRect, in: geo.size)
                        Rectangle()
                            .stroke(Color.red, lineWidth: 2)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                    }
                }
            }
            .frame(height: 300) // adapte si tu veux plus grand
            .onAppear {
                cameraModel.startSession()
            }
            .onDisappear {
                cameraModel.stopSession()
            }

            TextField("Nom Bluetooth du RVR", text: $vm.deviceName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()

            Button(vm.isConnected ? "Connecté" : "Connexion") {
                vm.connect()
            }
            .disabled(vm.isConnected)

            if vm.isConnected {
                Text("Direction : \(vm.heading)°")

                HStack(spacing: 20) {
                    Button("Gauche") { vm.turnLeft() }
                    Button("Avant") { vm.sendForward() }
                    Button("Droite") { vm.turnRight() }
                }
                HStack(spacing: 20) {
                    Button("Reculer") { vm.sendBack() }
                }
                Button("Déconnexion") { vm.disconnect() }
                    .padding(.top, 20)
            }

            Spacer()
        }
        .padding().onChange(of: cameraModel.detectedRects) { oldValue, newValue in
            for rect in newValue{
                autoMove(rect: rect)
            }
        }
    }
    
    private func autoMove(rect:CGRect){
        
    }

    private func rectFromNormalized(_ r: CGRect, in size: CGSize) -> CGRect {
        let x = r.origin.x * size.width
        let y = r.origin.y * size.height
        let w = r.size.width * size.width
        let h = r.size.height * size.height
        var rect = CGRect(x: x, y: y, width: w, height: h)
        return rect
    }
}
